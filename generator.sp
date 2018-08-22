#include <profiler>
#pragma newdecls required

public Plugin myinfo =
{
	name = "sourcemod.xml generator",
	author = "MCPAN (mcpan@foxmail.com), raziEiL [disawar1]",
	version = "1.2",
	url = "https://forums.alliedmods.net/member.php?u=73370"
}

#define	MAX_WIDTH 28
#define WIDTH MAX_WIDTH - 4

#define SPACE_CHAR	' '
#define SPACE_X4	"    "
#define SPACE_X8	"        "
#define SPACE_X12	"            "
#define SPACE_X16	"                "
#define SPACE_X28	"                            "

#define COMMENT_PARAM		"@param"
#define COMMENT_RETURN		"@return"
#define COMMENT_NORETURN	"@noreturn"
#define COMMENT_ERROR		"@error"

#define PATH_INCLUDE	"addons/sourcemod/scripting/include"
#define FILE_SOURCEMOD	"addons/sourcemod/plugins/sourcemod.xml"
#define FILE_FUNCTIONS	"addons/sourcemod/plugins/NPP_KEYWORDS_FUNCTION.sp"
#define FILE_DEFINES	"addons/sourcemod/plugins/NPP_KEYWORDS_CONSTANT.sp"
#define FILE_TYPES		"addons/sourcemod/plugins/NPP_KEYWORDS_CLASS_&_TAG.sp"

#define LOG		"logs\\generator.log"
char DEBUG[1024];

StringMap g_FuncTrie;
ArrayList g_FuncArray;
ArrayList g_ConstArray;
ArrayList g_ClassTagArray;
File g_FileSourcemodXML;
char g_MethodmapName[48], g_MethodmapTag[48];

public void OnPluginStart()
{
	BuildPath(Path_SM, DEBUG, sizeof(DEBUG), LOG);
	RegServerCmd("test", Cmd_Start);
}

public Action Cmd_Start(int argc)
{
	LogToFile(DEBUG, "\n\n\n\n--------------------------------------------");
	Handle prof = CreateProfiler();
	StartProfiling(prof);
	
	int size;
	char buffer[PLATFORM_MAX_PATH];
	ArrayList fileArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH)), g_TypesAndDefineArray = CreateArray(ByteCountToCells(64));
	
	g_FuncTrie = CreateTrie();
	g_FuncArray = CreateArray(ByteCountToCells(64));
	g_ConstArray = CreateArray(ByteCountToCells(64));
	g_ClassTagArray = CreateArray(ByteCountToCells(64));
	
	if ((size = ReadDirFileList(fileArray, PATH_INCLUDE, "inc")))
	{
		for (int i = 0; i < size; i++)
		{
			fileArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			ReadIncludeFile(buffer, i);
		}
	}

	SortADTArrayCustom(g_FuncArray, SortFuncADTArray);

	File file = OpenFile(FILE_FUNCTIONS, "wb");
	g_FileSourcemodXML = OpenFile(FILE_SOURCEMOD, "wb");
	
	g_FileSourcemodXML.WriteLine("<?xml version=\"1.0\" encoding=\"Windows-1252\" ?>");
	g_FileSourcemodXML.WriteLine("<NotepadPlus>");
	g_FileSourcemodXML.WriteLine("%s<AutoComplete language=\"sourcemod\">", SPACE_X4);
	
	if ((size = GetArraySize(g_FuncArray)))
	{
		int value;
		char funcname[64];
		for (int i = 0; i < size; i++)
		{
			g_FuncArray.GetString(i, funcname, 63);
			g_FuncTrie.GetValue(funcname, value)
			fileArray.GetString(value, buffer, PLATFORM_MAX_PATH-1);
			ReadIncludeFile(buffer, _, funcname);
			file.WriteLine("%s ", funcname);
		}
	}

	if ((size = GetArraySize(g_ClassTagArray)))
	{
		for (int i = 0; i < size; i++)
		{
			g_ClassTagArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			PushArrayString(g_TypesAndDefineArray, buffer);
		}
	}	
	if ((size = GetArraySize(g_ConstArray)))
	{
		for (int i = 0; i < size; i++)
		{
			g_ConstArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			PushArrayString(g_TypesAndDefineArray, buffer);
		}
	}
	
	SortADTArrayCustom(g_TypesAndDefineArray, SortFuncADTArray);
	SortADTArrayCustom(g_ConstArray, SortFuncADTArray);
	SortADTArrayCustom(g_ClassTagArray, SortFuncADTArray);
	
	if ((size = GetArraySize(g_TypesAndDefineArray)))
	{
		for (int i = 0; i < size; i++)
		{
			g_TypesAndDefineArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			g_FileSourcemodXML.WriteLine("%s<KeyWord name=\"%s\"/>", SPACE_X8, buffer);
		}
	}

	g_FileSourcemodXML.WriteLine("%s</AutoComplete>", SPACE_X4);
	g_FileSourcemodXML.WriteLine("</NotepadPlus>");
	
	delete file;
	delete fileArray;
	delete g_FuncTrie;
	delete g_FuncArray;
	delete g_FileSourcemodXML;
	delete g_TypesAndDefineArray;

	file = OpenFile(FILE_DEFINES, "wb");
	if ((size = GetArraySize(g_ConstArray)))
	{
		for (int i = 0; i < size; i++)
		{
			g_ConstArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			file.WriteLine("%s ", buffer);
		}
	}
	
	delete file;
	delete g_ConstArray;
	
	file = OpenFile(FILE_TYPES, "wb");
	if ((size = GetArraySize(g_ClassTagArray)))
	{
		for (int i = 0; i < size; i++)
		{
			g_ClassTagArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			file.WriteLine("%s ", buffer);
		}
	}
	
	delete file;
	delete g_ClassTagArray;

	StopProfiling(prof);
	PrintToServer("\n\t\t\t\tDone. time used %fs", GetProfilerTime(prof));
	delete prof;
	
	return Plugin_Handled;
}

void ReadIncludeFile(char[] filepath, int fileArrayIdx=-1, char[] search="")
{
	File file;
	if ((file = OpenFile(filepath, "rb")) == INVALID_HANDLE)
	{
		LogError("Open file faild '%s'", filepath);
		return;
	}
	
	int value, i;
	bool comment_buffer, found_comment, found_params, found_return, found_error, found_func, found_property;
	char temp[1024], buffer[1024], funcprefix[14], retval[32], funcname[128], funcparam[32];
	ArrayList array_param, array_return, array_error, array_note
	
	bool isMethodmap;
	int braceCount, propDeep, isBraceOnLine;	

	array_param = CreateArray(ByteCountToCells(1024));
	array_return = CreateArray(ByteCountToCells(1024));
	array_error = CreateArray(ByteCountToCells(1024));
	array_note = CreateArray(ByteCountToCells(1024));
	
	LogToFile(DEBUG, "ReadIncludeFile(PATH=%s, fileIndex=%d, search=%s)", filepath, fileArrayIdx, search);

	while (ReadFileLine(file, buffer, 1023))
	{
		if (!ReadString(buffer, 1023, found_comment))
		{
			if (found_comment)
			{
				found_params = false;
				found_return = false;
				found_error = false;
				ClearArray(array_param);
				ClearArray(array_return);
				ClearArray(array_error);
				ClearArray(array_note);
			}
			continue;
		}
		// TODO: ИГНОР КОМЕНТОВ
		isBraceOnLine = CountCharInString(buffer, '{');
		braceCount += isBraceOnLine - CountCharInString(buffer, '}');
		if (braceCount)
			LogToFile(DEBUG, "Brace deep=%d", braceCount);
		
		// check if in methodmap selection

		if (!isMethodmap){
		
			strcopy(funcprefix, 10, buffer);
			TrimString(funcprefix);
			
			if (strcmp(funcprefix, "methodmap") == 0 && ReadMethodmapHeader(buffer)){
				isMethodmap = true;
				LogToFile(DEBUG, "5. '%s', '%s'", g_MethodmapName, g_MethodmapTag);
				continue;
			}
		}
		else if (braceCount <= 0){
			isMethodmap = false;
		}

		if (found_property){
		
			if (braceCount <= propDeep){
				found_property = false;
				LogToFile(DEBUG, "Prop bracer END at line='%s'", buffer);
			}
			else {
				LogToFile(DEBUG, "skip prop line '%s'", buffer);
				continue;
			}
		}
		
		if (found_comment)
		{
			if (!search[0])
			{
				continue;
			}
			
			if ((value = FindCharInString2(buffer, '*')) != -1)
			{
				strcopy(buffer, 1023, buffer[++value]);
			}
			
			TrimString(buffer);
			
			if (!buffer[0])
			{
				continue;
			}
			
			if (StrContains(buffer, COMMENT_PARAM) == -1 &&
				StrContains(buffer, COMMENT_RETURN) == -1 &&
				StrContains(buffer, COMMENT_NORETURN) == -1 &&
				StrContains(buffer, COMMENT_ERROR) == -1)
			{
				if (found_params)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X28, buffer);
					PushArrayString(array_param, temp);
				}
				else if (found_return)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_return, temp);
				}
				else if (found_error)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_error, temp);
				}
				else
				{
					ReplaceString(buffer, 1023, "@note", "");
					ReplaceString(buffer, 1023, "@brief", "");
					
					TrimString(buffer);
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_note, temp);
				}
			}
			else if ((value = StrContains(buffer, COMMENT_PARAM)) != -1)
			{
				found_params = true;
				found_return = false;
				found_error = false;
				strcopy(buffer, 1023, buffer[value+6]);
				TrimString(buffer);
				
				if (buffer[0] && (value = FindCharInString2(buffer, SPACE_CHAR)) != -1)
				{
					strcopy(funcparam, value+1, buffer);
					strcopy(buffer, 1023, buffer[value]);
					TrimString(buffer);
					
					if ((value = WIDTH - value) > 0)
					{
						for (i = 0; i < value; i++)
						{
							temp[i] = SPACE_CHAR;
						}
						temp[value] = 0;
					}
					else
					{
						LogMessage("need space, set MAX_WIDTH >= %d", MAX_WIDTH - value);
					}
					
					Format(temp, 1023, "%s%s%s%s", SPACE_X4, funcparam, value > 0 ? temp : SPACE_X4, buffer);
					PushArrayString(array_param, temp);
				}
			}
			else if ((value = StrContains(buffer, COMMENT_RETURN)) != -1 || StrContains(buffer, COMMENT_NORETURN) != -1)
			{
				found_params = false;
				found_return = true;
				found_error = false;
				
				if (StrContains(buffer, COMMENT_NORETURN) != -1)
				{
					found_return = false;
					continue;
				}
				
				strcopy(buffer, 1023, buffer[value+7]);
				TrimString(buffer);
				FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
				PushArrayString(array_return, temp);
			}
			else if ((value = StrContains(buffer, COMMENT_ERROR)) != -1)
			{
				found_params = false;
				found_return = false;
				found_error = true;
				strcopy(buffer, 1023, buffer[value+6]);
				TrimString(buffer);
				FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
				PushArrayString(array_error, temp);
			}
			else
			{
				LogMessage(buffer);
			}
		}
		else if (StrContains(buffer, "#pragma deprecated") != -1 && ReadFileLine(file, buffer, 1023))
		{
			strcopy(funcprefix, 7, buffer);
			TrimString(funcprefix);
			
			do
			{
				if (strcmp(funcprefix, "stock") == 0 && buffer[0] == '}' ||
					strcmp(funcprefix, "stock") != 0 && FindCharInString2(buffer, ')') != -1)
				{
					break;
				}
			}
			while (ReadFileLine(file, buffer, 1023));
		}
		else
		{
			if ((value = StrContains(buffer, "#define ")) != -1)
			{
				if (search[0] ||
					StrContains(buffer, "_included") != -1 ||
					FindCharInString2(buffer, '(') != -1 ||
					FindCharInString2(buffer, '[') != -1)
				{
					continue;
				}
				
				strcopy(buffer, 1023, buffer[value+7]);
				TrimString(buffer);
				
				if ((value = FindCharInString2(buffer, SPACE_CHAR)) != -1)
				{
					strcopy(buffer, ++value, buffer);
					TrimString(buffer);
				}
				
				if (IsValidString(buffer) && FindStringInArray(g_ConstArray, buffer) == -1)
				{
					//LogToFile(DEBUG, "define=%s", buffer);
					PushArrayString(g_ConstArray, buffer);
				}
			}
			else if ((value = StrContains(buffer, "enum")) != -1)
			{
				if (search[0])
				{
					continue;
				}

				strcopy(buffer, 1023, buffer[value+4]);
				TrimString(buffer);

				strcopy(temp, 1023, buffer);
				ReplaceString(temp, 1023, "{", "");
				if (IsValidString(temp) && FindStringInArray(g_ConstArray, temp) == -1)
				{
					//PushArrayString(g_ConstArray, temp);
					PushArrayString(g_ClassTagArray, temp);
				}
				
				if ((value = FindCharInString2(buffer, '{')) != -1)
				{

					strcopy(temp, ++value, buffer);
					strcopy(buffer, 1023, buffer[value]);
					TrimString(temp);
					TrimString(buffer);
				
					if (WriteDefines(g_ConstArray, buffer, 1023, FindCharInString2(buffer, '}')))
					{

						while (ReadFileLine(file, buffer, 1023))
						{
							if (!WriteDefines(g_ConstArray, buffer, 1023, FindCharInString2(buffer, '}')))
							{
								break;
							}
						}
					}
				}
				else
				{
					while (ReadFileLine(file, buffer, 1023))
					{
						if (!ReadString(buffer, 1023, found_comment, comment_buffer) || comment_buffer)
						{
							continue;
						}
						
						if ((value = FindCharInString2(buffer, '{')) != -1)
						{
							strcopy(temp, ++value, buffer);
							strcopy(buffer, 1023, buffer[value]);
							TrimString(temp);
							TrimString(buffer);
							//LogToFile(DEBUG, "WriteDefines2 %s", buffer);
							if (WriteDefines(g_ConstArray, buffer, 1023, FindCharInString2(buffer, '}')))
							{
								
								while (ReadFileLine(file, buffer, 1023))
								{
									if (!ReadString(buffer, 1023, found_comment, comment_buffer) || comment_buffer)
									{
										continue;
									}
									
									if (!WriteDefines(g_ConstArray, buffer, 1023, FindCharInString2(buffer, '}')))
									{
										break;
									}
								}
							}
							break;
						}
					}
				}
			}
			else
			{
				strcopy(funcprefix, 8, buffer);
				TrimString(funcprefix);
				
				found_func = false;
				if (strcmp(funcprefix, "forward") == 0)
				{
					found_func = true;
					strcopy(buffer, 1015, buffer[8]);
				}
				else {

				 	strcopy(funcprefix, 7, buffer);
					TrimString(funcprefix);

					if (strcmp(funcprefix, "native") == 0)
					{
						found_func = true;
						strcopy(buffer, 1016, buffer[7]);
					}
					else {

						strcopy(funcprefix, 6, buffer);
						TrimString(funcprefix);

						if (strcmp(funcprefix, "stock") == 0)
						{
							found_func = true;
							strcopy(buffer, 1017, buffer[6]);
						//	LogToFile(DEBUG, "prefix='%s' funcname='%s'", funcprefix, buffer);
						}
						else {
						// TODO: добавить все функции public native
							// TODO: CLASS_%s_METHOD_%s
							// TODO: не читать строки в property
		
							strcopy(funcprefix, 14, buffer);
							TrimString(funcprefix);
							
							if (strcmp(funcprefix, "public native") == 0)
							{
								found_func = true;
								strcopy(buffer, 1009, buffer[14]);
								//LogToFile(DEBUG, "prefix='%s' funcname='%s'", funcprefix, buffer);
							}
							else {
								strcopy(funcprefix, 9, buffer);
								TrimString(funcprefix);
								
								if (strcmp(funcprefix, "property") == 0)
								{
									found_func = found_property = true;
									strcopy(buffer, 1014, buffer[9]);
									
									propDeep = braceCount - isBraceOnLine ? 1 : 0;
									
									LogToFile(DEBUG, "prefix='%s' funcname='%s'", funcprefix, buffer);
								}
							}
						}
					}
				 }
				
				if (found_func && ReadFuncString(buffer, retval, funcname, found_property, isBraceOnLine) && IsValidString(funcname))
				{
					if (isMethodmap){
					
						//LogToFile(DEBUG, "%s", funcname);
						
						if (g_MethodmapTag[0]){
						
							Format(funcname, 128, "METHODMAP_%s_%s_%s_%s", g_MethodmapName, g_MethodmapTag, found_property ? "PROP" : "METHOD", funcname);
						}
						else 
							Format(funcname, 128, "METHODMAP_%s_%s_%s", g_MethodmapName, found_property ? "PROP" : "METHOD", funcname);
						LogToFile(DEBUG, "%s", funcname);
					}
					
					if (search[0])
					{
						if (strcmp(funcname, search) == 0)
						{
							//LogToFile(DEBUG, "funcname=%s", funcname);
							FixXMLSyntax(funcname);
							WriteFileLine(g_FileSourcemodXML, "%s<KeyWord name=\"%s\" func=\"yes\">", SPACE_X8, funcname);
							WriteFileLine(g_FileSourcemodXML, "%s<Overload retVal=\"%s %s\" descr=\"", SPACE_X12, funcprefix, retval[0] ? retval : (isMethodmap ? g_MethodmapTag : "void"));
							

							if (IsValidString(retval) && FindStringInArray(g_ClassTagArray, retval) == -1)
							{
								//LogToFile(DEBUG, "type: %s", retval);
								PushArrayString(g_ClassTagArray, retval);
							}

							if ((value = GetArraySize(array_param)))
							{
								WriteFileLine(g_FileSourcemodXML, "Params:");
								for (i = 0; i < value; i++)
								{
									temp[0] = 0;
									GetArrayString(array_param, i, temp, 1023);

									FixXMLSyntax(temp);
									//LogToFile(DEBUG, "%s", temp);
									WriteFileLine(g_FileSourcemodXML, temp);
								}
							}
							if ((value = GetArraySize(array_note)))
							{
								WriteFileLine(g_FileSourcemodXML, "Notes:");
								for (i = 0; i < value; i++)
								{
									temp[0] = 0;
									GetArrayString(array_note, i, temp, 1023);
									FixXMLSyntax(temp);
									WriteFileLine(g_FileSourcemodXML, temp);
								}
							}
							if ((value = GetArraySize(array_error)))
							{
								WriteFileLine(g_FileSourcemodXML, "Error:");
								for (i = 0; i < value; i++)
								{
									temp[0] = 0;
									GetArrayString(array_error, i, temp, 1023);
									FixXMLSyntax(temp);
									WriteFileLine(g_FileSourcemodXML, temp);
								}
							}
							if ((value = GetArraySize(array_return)))
							{
								WriteFileLine(g_FileSourcemodXML, "Return:");
								for (i = 0; i < value; i++)
								{
									temp[0] = 0;
									GetArrayString(array_return, i, temp, 1023);
									FixXMLSyntax(temp);
									WriteFileLine(g_FileSourcemodXML, temp);
								}
							}
							
							WriteFileLine(g_FileSourcemodXML, "\">");
							
							if (buffer[0] == '(')
							{
								buffer[0] = SPACE_CHAR;
							}
							
							if (WriteFuncParams(g_FileSourcemodXML, buffer, 1023, FindCharInString2(buffer, ')')))
							{
								while (ReadFileLine(file, buffer, 1023))
								{
									if (!WriteFuncParams(g_FileSourcemodXML, buffer, 1023, FindCharInString2(buffer, ')')))
									{
										break;
									}
								}
							}
							
							WriteFileLine(g_FileSourcemodXML, "%s</Overload>", SPACE_X12);
							WriteFileLine(g_FileSourcemodXML, "%s</KeyWord>", SPACE_X8);
						}
						
						ClearArray(array_param);
						ClearArray(array_return);
						ClearArray(array_error);
						ClearArray(array_note);
					}
					else if (FindStringInArray(g_FuncArray, funcname) == -1)
					{
						PushArrayString(g_FuncArray, funcname);
						SetTrieValue(g_FuncTrie, funcname, fileArrayIdx);
					}
					else
						LogToFile(DEBUG,"UHM...same func name '%s'", funcname);
				}
			}
		}
	}
	
	CloseHandle(array_param);
	CloseHandle(array_return);
	CloseHandle(array_error);
	CloseHandle(array_note);
	CloseHandle(file);
}

int ReadString(char[] buffer, int maxlength, bool &found_comment=false, bool &comment_buffer=false)
{
	ReplaceString(buffer, maxlength, "\t", " ");
	ReplaceString(buffer, maxlength, "\"", "'");
	ReplaceString(buffer, maxlength, "%", "%%");
	
	static int len, i;
	if ((len = strlen(buffer)) && !found_comment)
	{
		for (i = 0; i < len; i++)
		{
			if (buffer[i] == '/' && buffer[i+1] == '/')
			{
				buffer[i] = 0;
				break;
			}
		}
	}
	
	static bool comment_start, comment_end;
	static int pos
	static char temp[1024]
	pos = 0
	comment_start = comment_end = false
	
	TrimString(buffer);
	if ((len = strlen(buffer)))
	{
		if (found_comment)
			comment_buffer = true;

		if ((pos = StrContains(buffer, "/*")) != -1)
		{
			comment_start = true;
			strcopy(temp, 1023, buffer[pos+2]);
			buffer[pos] = 0;
			TrimString(buffer);
			
			if ((pos = StrContains(temp, "*/")) != -1)
			{
				comment_end = true;
				strcopy(temp, 1023, temp[pos+2]);
				TrimString(temp);
			}
			else
			{
				temp[0] = 0;
			}
			
			if (strlen(buffer) || strlen(temp))
			{
				comment_buffer = false;
				Format(buffer, maxlength, "%s%s", buffer, temp);
			}
			temp[0] = 0;
		}
		else if ((pos = StrContains(buffer, "*/")) != -1)
		{
			comment_end = true;
			comment_buffer = false;
			strcopy(buffer, maxlength, buffer[pos+2]);
		}
		
		TrimString(buffer);
		len = strlen(buffer);
	}
	
	if (comment_start && comment_end)
	{
		comment_start = false;
		comment_end = false;
	}
	
	if (comment_start)
	{
		found_comment = comment_start;
	}
	else if (comment_end)
	{
		found_comment = comment_start;
	}
	
	return len;
}

bool ReadFuncString(char[] buffer, char[] retval, char[] funcname, bool found_property = false, int isBraceOnLine = 0)
{
	retval[0] = 0;
	funcname[0] = 0;
	
	static int pos, len;
	if ((len = strlen(buffer)))
	{
		if (found_property){
		
			if (isBraceOnLine)
				pos = FindCharInString2(buffer, '{');
			else
				pos = len;
		}	
		else
			pos = FindCharInString2(buffer, '(');
		
		if (pos == -1) 
			return false;
		
		strcopy(funcname, pos+1, buffer);
		strcopy(buffer, len, buffer[pos]);
		
		TrimString(funcname);
		
		if (strcmp(funcname, "VerifyCoreVersion") == 0 ||
			StrContains(funcname, "operator") != -1)
		{
			return false;
		}
		
		if ((pos = FindCharInString2(funcname, 32)) != -1 || (pos = FindCharInString2(funcname, 58)) != -1)
		{
			strcopy(retval, ++pos, funcname);
			strcopy(funcname, len, funcname[pos]);

			if(retval[0] == 70) // little fix 'F' -> 'f'
				retval[0] = 102
		}
		
		return true;
	}
	
	return false;
}

bool ReadMethodmapHeader(char[] buffer)
{
	// ex: 'methodmap ArrayList < Handle {'
	// result: str1=ArrayList, str2=Handle

	g_MethodmapName[0] = 0;
	g_MethodmapTag[0] = 0;
	static int pos, len;
	
	if ((len = strlen(buffer))){
	
		static char str[1024];
		str[0] = 0;
		strcopy(str, 1024, buffer);
		strcopy(str, len, str[10]);
		TrimString(str);		
		
		LogToFile(DEBUG, "1. '%s'", buffer);
		
		if ((pos = FindCharInString2(str, SPACE_CHAR)) != -1)
		{
			LogToFile(DEBUG, "2. space_pos=%d, ", pos);
			
			strcopy(g_MethodmapName, pos+1, str);
			strcopy(str, len, str[pos]);
			
			LogToFile(DEBUG, "3. '%s'", str);
			
			if (ReplaceString(str, len, "<", "")){
				
				TrimString(str);
				LogToFile(DEBUG, "4. '%s'", str);
				
				if ((pos = FindCharInString2(str, SPACE_CHAR)) != -1){
					strcopy(g_MethodmapTag, pos+1, str);
					if (!IsValidString(g_MethodmapTag))
						g_MethodmapTag[0] = 0;
					else if (FindStringInArray(g_ClassTagArray, g_MethodmapTag) == -1)
						PushArrayString(g_ClassTagArray, g_MethodmapTag);
				}
			}
			
			if (IsValidString(g_MethodmapName)){
				if (FindStringInArray(g_ClassTagArray, g_MethodmapName) == -1)
					PushArrayString(g_ClassTagArray, g_MethodmapName);
				return true;
			}
				
			return false;
		}
	}
	return false;
}

bool WriteFuncParams(Handle handle, char[] buffer, int maxlength, int pos)
{
	if (pos != -1)
	{
		buffer[pos] = 0;
	}
	
	ReplaceString(buffer, maxlength, "\t", " ");
	ReplaceString(buffer, maxlength, "\"", "'");
	ReplaceString(buffer, maxlength, "%", "%%");
	
	TrimString(buffer);
	if (buffer[0])
	{
		static char funcparams[32][256];
		static int count, i
		count = ExplodeString(buffer, ",", funcparams, sizeof(funcparams), sizeof(funcparams[]));
		for (i = 0; i < count; i++)
		{
			TrimString(funcparams[i]);
			if (funcparams[i][0])
			{
				FixXMLSyntax(funcparams[i]);
				WriteFileLine(handle, "%s<Param name=\"%s\"/>", SPACE_X16, funcparams[i]);
				funcparams[i][0] = 0;
			}
		}
	}
	
	return pos == -1;
}

bool WriteDefines(Handle &handle, char[] buffer, int maxlength, int pos)
{
	if (pos != -1)
	{
		buffer[pos] = 0;
	}
	
	ReplaceString(buffer, maxlength, "\t", " ");
	ReplaceString(buffer, maxlength, "\"", "'");
	
	TrimString(buffer);
	if (buffer[0])
	{
		static char defines_temp[32][64];
		int pos2, i, value
		value = ExplodeString(buffer, ",", defines_temp, sizeof(defines_temp), sizeof(defines_temp[]));
		for (i = 0; i < value; i++)
		{
			TrimString(defines_temp[i]);
			if (defines_temp[i][0])
			{
				if ((pos2 = FindCharInString2(defines_temp[i], '=')) != -1)
				{
					defines_temp[i][pos2] = 0;
					TrimString(defines_temp[i]);
				}
				
				if (IsValidString(defines_temp[i]) && FindStringInArray(handle, defines_temp[i]) == -1)
				{
					PushArrayString(handle, defines_temp[i]);
				}
				
				defines_temp[i][0] = 0;
			}
		}
	}
	
	return pos == -1;
}

bool IsValidString(char[] buffer)
{
	TrimString(buffer);
	return (buffer[0] &&
			FindCharInString2(buffer, SPACE_CHAR) == -1 &&
			FindCharInString2(buffer, '*') == -1 &&
			FindCharInString2(buffer, '/') == -1 &&
			FindCharInString2(buffer, ':') == -1 &&
			FindCharInString2(buffer, '(') == -1 &&
			FindCharInString2(buffer, '[') == -1 &&
			FindCharInString2(buffer, ']') == -1 &&
			FindCharInString2(buffer, ')') == -1 &&
			FindCharInString2(buffer, '%') == -1 &&
			StrContains(buffer, "__FLOAT") == -1);
}

public int SortFuncADTArray(int index1, int index2, Handle array, Handle hndl)
{
	char str1[64], str2[64];
	GetArrayString(array, index1, str1, 63);
	GetArrayString(array, index2, str2, 63);
	return strcmp(str1, str2, false);
}

stock int ReadDirFileList(Handle &fileArray, const char[] dirPath, const char[] fileExt="")
{
	Handle dir;
	if ((dir = OpenDirectory(dirPath)) == INVALID_HANDLE)
	{
		LogError("Open dir faild '%s'", dirPath);
		return 0;
	}
	
	FileType fileType;
	char buffer[PLATFORM_MAX_PATH], currentPath[PLATFORM_MAX_PATH];
	ArrayList pathArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
	
	buffer[0] = 0;
	currentPath[0] = 0;
	
	while (ReadDirEntry(dir, buffer, PLATFORM_MAX_PATH-1, fileType)
		|| ReadSubDirEntry(dir, buffer, PLATFORM_MAX_PATH-1, fileType, pathArray, dirPath, currentPath))
	{
		switch (fileType)
		{
			case FileType_Directory:
			{
				if (strcmp(buffer, ".") != 0 && strcmp(buffer, "..") != 0)
				{
					Format(buffer, PLATFORM_MAX_PATH-1, "%s/%s", currentPath, buffer);
					PushArrayString(pathArray, buffer);
				}
			}
			case FileType_File:
			{
				if (fileExt[0] && !CheckFileExt(buffer, fileExt))
				{
					continue;
				}
				
				Format(buffer, PLATFORM_MAX_PATH-1, "%s%s/%s", dirPath, currentPath, buffer);
				PushArrayString(fileArray, buffer);
			}
		}
	}
	
	CloseHandle(pathArray);
	if (dir != INVALID_HANDLE)
	{
		CloseHandle(dir);
	}
	
	return GetArraySize(fileArray);
}

stock bool ReadSubDirEntry(Handle &dir, char[] buffer, int maxlength, FileType &fileType, Handle &pathArray, const char[] dirPath, char[] currentPath)
{
	if (!GetArraySize(pathArray))
	{
		return false;
	}
	
	GetArrayString(pathArray, 0, currentPath, maxlength);
	RemoveFromArray(pathArray, 0);
	
	CloseHandle(dir);
	dir = INVALID_HANDLE;
	
	FormatEx(buffer, maxlength, "%s%s", dirPath, currentPath);
	if ((dir = OpenDirectory(buffer)) == INVALID_HANDLE)
	{
		LogError("Open sub dir faild '%s'", buffer);
		return false;
	}
	
	return ReadDirEntry(dir, buffer, maxlength, fileType);
}

stock bool CheckFileExt(char[] filename, const char[] extname)
{
	int pos;
	if ((pos = FindCharInString2(filename, '.', true)) == -1)
	{
		return false;
	}
	
	char ext[32];
	strcopy(ext, 31, filename[++pos]);
	return strcmp(ext, extname, false) == 0;
}

int FindCharInString2(const char[] str, char c, bool reverse = false)
{
	static int len, i
	len = strlen(str);
	
	if (!reverse) {
		for (i = 0; i < len; i++) {
			if (str[i] == c)
				return i;
		}
	} else {
		for (i = len - 1; i >= 0; i--) {
			if (str[i] == c)
				return i;
		}
	}

	return -1;
}

int CountCharInString(const char[] str, char c)
{
	static int len, i, count;
	len = strlen(str);
	//count = 0;
	
	for (i = count = 0; i < len; i++) {
		if (str[i] == c)
			count++;
	}

	return count;
}

public void FixXMLSyntax(char[] str)
{
	ReplaceString(str, 1023, "&", "&amp;");
	ReplaceString(str, 1023, "<", "&lt;");
	ReplaceString(str, 1023, ">", "&gt;");
	ReplaceString(str, 1023, "'", "&apos;");
	ReplaceString(str, 1023, "\"", "&quot;");
}
