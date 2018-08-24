#define PLUGIN_VERSION "1.2.4"

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <profiler>

// TODO: check -> file, property 
// TODO: Не верная сортировка xml.? Не высвечивается поиск по функциям METHODMAP_..., FindStringInArray, strl
// TODO: check @param -> KvGetVector

//-----------------------------------
// Pre-compiler option
//-----------------------------------
#define DEBUG_BYTES (DEBUG_BYTE_LOG_FILE|DEBUG_BYTE_FUNC_PARAM|DEBUG_BYTE_ERROR|DEBUG_BYTE_COMMON) // bytes mask
// write to NPP_STYLE_FUNCTION file all strings but fake mothodmaps (e.g., METHODMAP_ArrayList_Handle_METHOD_GetArray)
#define ADD_NPP_STYLE_METHODMAP 1
#define ADD_DOCS_OPERATORS_MISC 1
#define ADD_DOCS_VARIABLES		1
// -----------------------------------

// bits
#define DEBUG_BYTE_PRINT_SERVER	1
#define DEBUG_BYTE_LOG_FILE		2
#define DEBUG_BYTE_COMMON		4
#define DEBUG_BYTE_FUNC_PARAM 	8
#define DEBUG_BYTE_METHODMAP 	16
#define DEBUG_BYTE_BRACKET 		32
#define DEBUG_BYTE_COMMENTARY	64
#define DEBUG_BYTE_XML			128
#define DEBUG_BYTE_ERROR		256

#define DEBUG_BYTE_ALL			510

#define DEBUG_TAG_COMMOM 		0
#define DEBUG_TAG_FUNC_PARAM 	1
#define DEBUG_TAG_METHODMAP 	2
#define DEBUG_TAG_BRACKET 		3
#define DEBUG_TAG_COMMENTARY 	4
#define DEBUG_TAG_XML 			5
#define DEBUG_TAG_ERROR 		6

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
#define FILE_SOURCEMOD	"addons/sourcemod/plugins/NPP/sourcemod.xml"
#define FILE_OPERATORS	"addons/sourcemod/plugins/NPP/NPP_STYLE_OPERATORS.sp"
#define FILE_FUNCTIONS	"addons/sourcemod/plugins/NPP/NPP_STYLE_FUNCTION.sp"
#define FILE_CONSTANT	"addons/sourcemod/plugins/NPP/NPP_STYLE_CONSTANT.sp"
#define FILE_MISC		"addons/sourcemod/plugins/NPP/NPP_STYLE_MISC.sp"
// ( ) [ ] ; , - style separator
#define NPP_STYLE_OPERATORS "( ) [ ] ; , * / % + - << >> >>> < > <= >= == != & && ^ | || ? : = += -= *= /= %= &= ^= |= <<= >>= >>>= ++ -- ~ !"
#define NPP_STYLE_OPERATORS_MISC "for if else do while switch case default return break delete continue new decl public stock const enum forward static funcenum functag native sizeof view_as true false union function methodmap typedef property struct this"
#define NPP_STYLE_VARIABLES "bool char int float Handle"

#define LOG		"logs\\generator.log"

#define PARAM 0
#define NOTES 1
#define ERROR 2
#define RETURN 3
#define TOTAL_COMMENT 4

public Plugin myinfo =
{
	name = "Npp-generator",
	author = "MCPAN (mcpan@foxmail.com), raziEiL [disawar1]",
	description = "Generate auto-completion files & sourcemod.xml docs",
	version = PLUGIN_VERSION,
	url = "https://github.com/raziEiL/SourceMod-Npp-Docs"
}

char DEBUG[1024];
StringMap g_FuncTrie;
ArrayList g_FuncArray, g_ConstArray, g_MiscArray; // Class ,tag, vars
File g_FileSourcemodXML;
char g_MethodmapName[48], g_MethodmapTag[48];
char g_FuncPrefix[][] = {"forward", "native", "stock", "public native", "property", "public" };
char g_CommentType[TOTAL_COMMENT][] = { "Params:", "Notes:", "Error:", "Return:" };
char g_Debug[][24] = {"COMMON", "FUNC PARAM", "METHODMAP", "BRACKET", "COMMENTARY", "XML", "ERROR"};
int g_XMLFixCount;

public void OnPluginStart()
{
#if (DEBUG_BYTES & DEBUG_BYTE_LOG_FILE)
	BuildPath(Path_SM, DEBUG, sizeof(DEBUG), LOG);
#endif
	RegServerCmd("sm_makedocs", Cmd_Start, "starts to parse SourceMod includes and generates output files");
}

public Action Cmd_Start(int argc)
{
	PrintToServer("starts to parse includes! (debug = %d)", DEBUG_BYTES);
	Debug(DEBUG_BYTE_COMMON, "--------------------------------------------");
	g_XMLFixCount = 0;
	Handle prof = CreateProfiler();
	StartProfiling(prof);
	CreateDirectory("addons/sourcemod/plugins/NPP", 511);

	int i, size, count[3];
	char buffer[PLATFORM_MAX_PATH];
	ArrayList fileArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH)), g_CommonArray = CreateArray(ByteCountToCells(64));

	g_FuncTrie = CreateTrie();
	g_FuncArray = CreateArray(ByteCountToCells(64));
	g_ConstArray = CreateArray(ByteCountToCells(64));
	g_MiscArray = CreateArray(ByteCountToCells(64));

	Debug(DEBUG_BYTE_COMMON, "> --------------------------------");
	Debug(DEBUG_BYTE_COMMON, "> PARSING STARTED");
	Debug(DEBUG_BYTE_COMMON, "> --------------------------------");
	Debug(DEBUG_BYTE_COMMON, "> I. ADD IN ARRAY");
	Debug(DEBUG_BYTE_COMMON, "> --------------------------------");

	if ((size = ReadDirFileList(fileArray, PATH_INCLUDE, "inc")))
	{
		for (i = 0; i < size; i++)
		{
			fileArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			ReadIncludeFile(buffer, i);
		}
	}

	Debug(DEBUG_BYTE_COMMON, "> --------------------------------");
	Debug(DEBUG_BYTE_COMMON, "> II. SORT ARRAY AND WRITE");
	Debug(DEBUG_BYTE_COMMON, "> --------------------------------");

	SortADTArrayCustom(g_FuncArray, SortFuncADTArray);
	File file = OpenFile(FILE_FUNCTIONS, "wb");
	g_FileSourcemodXML = OpenFile(FILE_SOURCEMOD, "wb");
	
	g_FileSourcemodXML.WriteLine("<?xml version=\"1.0\" encoding=\"Windows-1252\" ?>");
	g_FileSourcemodXML.WriteLine("<NotepadPlus>");
	g_FileSourcemodXML.WriteLine("%s<AutoComplete language=\"sourcemod\">", SPACE_X4);
	g_FileSourcemodXML.WriteLine("%s<Environment ignoreCase=\"no\"/>", SPACE_X4); // fix

	if ((count[0] = size = GetArraySize(g_FuncArray)))
	{
		int value;
		char funcname[64];
		for (i = 0; i < size; i++)
		{
			g_FuncArray.GetString(i, funcname, 63);
			g_FuncTrie.GetValue(funcname, value);
			fileArray.GetString(value, buffer, PLATFORM_MAX_PATH-1);
			ReadIncludeFile(buffer, _, funcname);
			if (ADD_NPP_STYLE_METHODMAP && StrContains(funcname, "METHODMAP_") != -1)
				continue;
			file.WriteLine("%s ", funcname);
		}
	}
	
#if ADD_DOCS_OPERATORS_MISC
	char temp[42][32];
	ExplodeString(NPP_STYLE_OPERATORS_MISC, " ", temp, sizeof(temp), sizeof(temp[]));

	for (i = 0; i < sizeof(temp); i++)
	{
		if (!temp[i]) 
			break;
		
		if (FindStringInArray(g_CommonArray, temp[i]) == -1)
			PushArrayString(g_CommonArray, temp[i]);
	}
#endif
#if ADD_DOCS_VARIABLES
	char temp2[5][16];
	ExplodeString(NPP_STYLE_VARIABLES, " ", temp2, sizeof(temp2), sizeof(temp2[]));

	for (i = 0; i < sizeof(temp2); i++)
	{
		if (!temp2[i]) 
			break;
		
		if (FindStringInArray(g_MiscArray, temp2[i]) == -1)
			PushArrayString(g_MiscArray, temp2[i]);
	}
#endif
	
	if ((count[1] = size = GetArraySize(g_MiscArray)))
	{
		for (i = 0; i < size; i++)
		{
			g_MiscArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			PushArrayString(g_CommonArray, buffer);
		}
	}
	if ((count[2] = size = GetArraySize(g_ConstArray)))
	{
		for (i = 0; i < size; i++)
		{
			g_ConstArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			PushArrayString(g_CommonArray, buffer);
		}
	}
	
	SortADTArrayCustom(g_CommonArray, SortFuncADTArray);
	SortADTArrayCustom(g_ConstArray, SortFuncADTArray);
	SortADTArrayCustom(g_MiscArray, SortFuncADTArray);

	if ((size = GetArraySize(g_CommonArray)))
	{
		for (i = 0; i < size; i++)
		{
			g_CommonArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
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
	delete g_CommonArray;

	file = OpenFile(FILE_CONSTANT, "wb");
	if ((size = GetArraySize(g_ConstArray)))
	{
		for (i = 0; i < size; i++)
		{
			g_ConstArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			file.WriteLine("%s ", buffer);
		}
	}

	delete file;
	delete g_ConstArray;

	file = OpenFile(FILE_MISC, "wb");
	if ((size = GetArraySize(g_MiscArray)))
	{
		for (i = 0; i < size; i++)
		{
			g_MiscArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			file.WriteLine("%s ", buffer);
		}
	}

	delete file;
	delete g_MiscArray;
	
	file = OpenFile(FILE_OPERATORS, "wb");
	file.WriteLine("%s\n", NPP_STYLE_OPERATORS);
	file.WriteLine(NPP_STYLE_OPERATORS_MISC);
	delete file;
	
	StopProfiling(prof);
	PrintToServer("\n\t\t\t\t> Job Done! Time used: %.2fs. XML fixed: %d error. Func: %d, Misc %d, Define %d", GetProfilerTime(prof), g_XMLFixCount, count[0], count[1], count[2]);
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
	bool comment_buffer, found_comment, found_params, found_return, found_error, found_func, found_property, in_property;
	char temp[1024], buffer[1024], funcprefix[14], retval[32], funcname[128], funcparam[32], lastPropName[128];
	
	ArrayList array_comment[TOTAL_COMMENT];
	for (int elem = 0; elem < TOTAL_COMMENT; elem++)
		array_comment[elem] = CreateArray(ByteCountToCells(1024));
	
	bool isMethodmap, diveInDeep;
	int nextDeep, propDeep, currentDeep, commentDeep, tempVal, tempVal2;


	Debug(DEBUG_BYTE_COMMON, "ReadIncludeFile(PATH=%s, fileIndex=%d, search=%s)", filepath, fileArrayIdx, search);

	while (ReadFileLine(file, buffer, 1023))
	{
		if (!ReadString(buffer, 1023, found_comment))
		{
			if (found_comment)
			{
				found_params = false;
				found_return = false;
				found_error = false;

				for (i = 0; i < TOTAL_COMMENT; i++)
					ClearArray(array_comment[i]);
					
				commentDeep = nextDeep;
			}
			continue;
		}

		diveInDeep = false;

		if (!found_comment){

			tempVal = CountCharInString(buffer, '{');
			tempVal2 = CountCharInString(buffer, '}');

			diveInDeep = tempVal > tempVal2;
			nextDeep += tempVal - tempVal2;
			currentDeep = nextDeep - (diveInDeep ? 1 : 0);
			Debug(DEBUG_BYTE_BRACKET, "%d - current, %d - next", currentDeep, nextDeep);

			// check if in methodmap selection

			if (!isMethodmap){

				strcopy(funcprefix, 10, buffer);
				TrimString(funcprefix);

				if (strcmp(funcprefix, "methodmap") == 0 && ReadMethodmapHeader(buffer)){
					isMethodmap = true;
					Debug(DEBUG_BYTE_METHODMAP, "5. '%s', '%s'", g_MethodmapName, g_MethodmapTag);
					continue;
				}
			}
			else if (nextDeep <= 0){
				isMethodmap = false;
			}

			if (found_property){

				if (nextDeep <= propDeep){
					found_property = in_property = false;
					Debug(DEBUG_BYTE_BRACKET, "prop brackets ended");
				}
				else {
					in_property = true;
				}
			}
		}
		if (found_comment)
		{
			if (!search[0])
			{
				Debug(DEBUG_BYTE_COMMENTARY, "skip comment");
				continue;
			}

			Debug(DEBUG_BYTE_COMMENTARY, "'%s'", buffer);

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
					PushArrayString(array_comment[PARAM], temp);
				}
				else if (found_return)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_comment[RETURN], temp);
				}
				else if (found_error)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_comment[ERROR], temp);
				}
				else
				{
					ReplaceString(buffer, 1023, "@note", "");
					ReplaceString(buffer, 1023, "@brief", "");

					TrimString(buffer);
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_comment[NOTES], temp);
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
					PushArrayString(array_comment[PARAM], temp);
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
				PushArrayString(array_comment[RETURN], temp);
			}
			else if ((value = StrContains(buffer, COMMENT_ERROR)) != -1)
			{
				found_params = false;
				found_return = false;
				found_error = true;
				strcopy(buffer, 1023, buffer[value+6]);
				TrimString(buffer);
				FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
				PushArrayString(array_comment[ERROR], temp);
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
				if (IsValidString(temp) && FindStringInArray(g_MiscArray, temp) == -1)
				{
					PushArrayString(g_MiscArray, temp);
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
				found_func = false;

				for (i = 0; i < sizeof(g_FuncPrefix); i++){

					tempVal = strlen(g_FuncPrefix[i])+1;
					strcopy(funcprefix, tempVal, buffer);
					TrimString(funcprefix);

					if (strcmp(funcprefix, g_FuncPrefix[i]) == 0){
						found_func = true;
						strcopy(buffer, sizeof(buffer)-tempVal, buffer[tempVal]);
						Debug(DEBUG_BYTE_COMMON, "Ffound: funcprefix='%s' funcname='%s'", funcprefix, buffer);
						break;
					}
				}
				// is property
				if (strcmp(funcprefix, g_FuncPrefix[4]) == 0){

					found_property = true;
					propDeep = currentDeep;
				}
	
				if (found_func)
				{
					if (ReadFuncString(buffer, retval, funcname, found_property, in_property) && IsValidString(funcname)){
	
						if (isMethodmap){

							Debug(DEBUG_BYTE_COMMON, "%s", funcname);
							// TODO: доделать проперти
							if (!in_property)
								lastPropName = funcname;
							else
								Format(funcname, 128, "%s_%s", lastPropName, funcname);
							
							if (found_property)
								temp = "PROP";
							else if (!retval[0])
								temp = "CONSTRUCTOR";
							else
								temp = "METHOD";

							if (g_MethodmapTag[0])
								Format(funcname, 128, "METHODMAP_%s_%s_%s_%s", g_MethodmapName, g_MethodmapTag, temp, funcname);
							else
								Format(funcname, 128, "METHODMAP_%s_%s_%s", g_MethodmapName, temp, funcname);

							Debug(DEBUG_BYTE_COMMON, "Ftype:Methodmap: %s", funcname);
						}
						else
							Debug(DEBUG_BYTE_COMMON, "Ftype:Normal: funcname='%s', retval='%s' ", funcname, retval[0] ? retval : "void");

						if (search[0])
						{
							if (strcmp(funcname, search) == 0)
							{
								WriteFileLine(g_FileSourcemodXML, "%s<KeyWord name=\"%s\" func=\"yes\">", SPACE_X8, funcname);
								WriteFileLine(g_FileSourcemodXML, "%s<Overload retVal=\"%s %s\" descr=\"", SPACE_X12, funcprefix, retval[0] ? retval : (isMethodmap ? g_MethodmapTag : "void"));

								if (IsValidString(retval) && FindStringInArray(g_MiscArray, retval) == -1)
								{
									PushArrayString(g_MiscArray, retval);
								}

								Debug(DEBUG_BYTE_BRACKET, "currentDeep=%d, commentDeep=%d", currentDeep, commentDeep);

								if (currentDeep == commentDeep)
								{
									for (int comment = 0; comment < TOTAL_COMMENT; comment++){
									
										if ((value = GetArraySize(array_comment[comment])))
										{
											WriteFileLine(g_FileSourcemodXML, g_CommentType[comment]);
											for (i = 0; i < value; i++)
											{
												temp[0] = 0;
												GetArrayString(array_comment[comment], i, temp, 1023);
												ValidateXML(temp, 1023);
												WriteFileLine(g_FileSourcemodXML, temp);
											}
										}
									}
								}
								
								WriteFileLine(g_FileSourcemodXML, "\">");

								if (!found_property){
								
									if (buffer[0] == '(')
									{
										value = 1;
										buffer[0] = SPACE_CHAR;
									}
									else 
										value = 0;
												
									do 
									{
										value += CountCharInString(buffer, '(') - CountCharInString(buffer, ')');
										WriteFuncParams(g_FileSourcemodXML, buffer, 1023, value > 0) ;
									} while (value > 0 && ReadFileLine(file, buffer, 1023));		
								}
								
								WriteFileLine(g_FileSourcemodXML, "%s</Overload>", SPACE_X12);
								WriteFileLine(g_FileSourcemodXML, "%s</KeyWord>", SPACE_X8);
								break;
							}
						}
						else if (FindStringInArray(g_FuncArray, funcname) == -1)
						{
							PushArrayString(g_FuncArray, funcname);
							SetTrieValue(g_FuncTrie, funcname, fileArrayIdx);
						}
						else
							Debug(DEBUG_BYTE_ERROR,"UHM...same func name '%s'", funcname);
					}

					for (i = 0; i < TOTAL_COMMENT; i++)			
						ClearArray(array_comment[i]);

				}
			}
		}
	}

	for (i = 0; i < TOTAL_COMMENT; i++)			
		CloseHandle(array_comment[i]);
	
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
	static int pos;
	static char temp[1024];
	pos = 0;
	comment_start = comment_end = false;

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

bool ReadFuncString(char[] buffer, char[] retval, char[] funcname, bool found_property = false, bool in_property = false)
{
	retval[0] = 0;
	funcname[0] = 0;

	static int pos, len;
	if ((len = strlen(buffer)))
	{
		if (found_property && !in_property){

			if ((pos = FindCharInString2(buffer, '{')) == -1)
				pos = len;
		}
		else if ((pos = FindCharInString2(buffer, '(')) == -1)
			return false;

		strcopy(funcname, pos+1, buffer);
		strcopy(buffer, len, buffer[pos]);

		TrimString(funcname);
		
		Debug(DEBUG_BYTE_COMMON, "ReadFuncString -> '%s'", funcname);
		
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
				retval[0] = 102;
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

		Debug(DEBUG_BYTE_METHODMAP, "1. '%s'", buffer);

		if ((pos = FindCharInString2(str, SPACE_CHAR)) != -1)
		{
			Debug(DEBUG_BYTE_METHODMAP, "2. space_pos=%d, ", pos);

			strcopy(g_MethodmapName, pos+1, str);
			strcopy(str, len, str[pos]);

			Debug(DEBUG_BYTE_METHODMAP, "3. '%s'", str);

			if (ReplaceString(str, len, "<", "")){

				TrimString(str);
				Debug(DEBUG_BYTE_METHODMAP, "4. '%s'", str);

				if ((pos = FindCharInString2(str, SPACE_CHAR)) != -1){
					strcopy(g_MethodmapTag, pos+1, str);
					if (!IsValidString(g_MethodmapTag))
						g_MethodmapTag[0] = 0;
					else if (FindStringInArray(g_MiscArray, g_MethodmapTag) == -1)
						PushArrayString(g_MiscArray, g_MethodmapTag);
				}
			}

			if (IsValidString(g_MethodmapName)){
				if (FindStringInArray(g_MiscArray, g_MethodmapName) == -1)
					PushArrayString(g_MiscArray, g_MethodmapName);
				return true;
			}

			return false;
		}
	}
	return false;
}

void WriteFuncParams(Handle handle, char[] buffer, int maxlength, bool isLineBreaked = false)
{
	static char buildStr[2048];
	Format(buildStr, sizeof(buildStr), "%s%s", buildStr, buffer);
	
	Debug(DEBUG_BYTE_FUNC_PARAM, "Split func params (is line breaked=%d):", isLineBreaked);
	Debug(DEBUG_BYTE_FUNC_PARAM, "src: '%s'", buildStr);
	
	if (isLineBreaked)
		return;
		
	ReplaceString(buildStr, maxlength, "\t", " ");
	ReplaceString(buildStr, maxlength, "\"", "'");
	ReplaceString(buildStr, maxlength, "%", "%%");
	TrimString(buildStr);
	
	if (buildStr[0]){
	
		static int count, i, blah, bracet, lastpos;
		static bool isEnd;
		static char temp[128], execlude[] = "{;)";
		maxlength = strlen(buildStr);
		
		for (i = bracet = lastpos = count = 0; i < maxlength; i++){
		
			if (buildStr[i] == '{')
				bracet++;
			else if (buildStr[i] == '}')
				bracet--;
				
			isEnd = i + 1 == maxlength;
			
			if (!bracet && buildStr[i] == ',' || isEnd){
				
				strcopy(temp, i + 1 - lastpos - (lastpos && !isEnd ? 1 : 0), buildStr[lastpos + (lastpos ? 1 : 0)]);
				TrimString(temp);
				lastpos = i;

				if (isEnd){

					for (blah = 0; blah < 3; blah++){
					
						lastpos = strlen(temp)-1;
						if (lastpos < 0){
						
							Debug(DEBUG_BYTE_ERROR, "Array index out-of-bounds! No params? Called from %s", g_Debug[DEBUG_TAG_FUNC_PARAM]);
							break;
						}			
							
						if (temp[lastpos] == execlude[blah]){
							temp[lastpos] = 0;
							TrimString(temp);
						}
					}
				}
				if (temp[0]){
				
					ValidateXML(temp, 128);
					Debug(DEBUG_BYTE_FUNC_PARAM, "%d. '%s'", ++count, temp);
					WriteFileLine(handle, "%s<Param name=\"%s\"/>", SPACE_X16, temp);
				}	
			}
		}
	}
	buildStr[0] = 0;
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
		int pos2, i, value;
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
			StrContains(buffer, "__FLOAT") == -1 &&
			StrContains(buffer, "_SetNTVOptional") == -1);
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
	static int len, i;
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

	for (i = count = 0; i < len; i++) {
		if (str[i] == c)
			count++;
	}

	return count;
}

public void ValidateXML(char[] text, int size)
{
	static char buffer[1024];
	char search[] = "&amp;";

	static int i, offset, text_len, search_len;

	text_len = strlen(text);
	search_len = strlen(search);

	Debug(DEBUG_BYTE_XML, "text = '%s', search = '%s'", text, search);

	for (i = 0; i < text_len; i++){
	
		if (text[i] == search[0]){
		
			Debug(DEBUG_BYTE_XML, "match at pos: %d", i);
			
			for (offset = 1; offset < search_len; offset++){
		
				if (i+offset >= size){
					Debug(DEBUG_BYTE_XML, "offset out of range: %d/%d!", offset, size);
					break;
				}

				if (text[i+offset] != search[offset]){
				
					strcopy(buffer, i+1, text);
					offset = strlen(buffer) + strlen(search) + strlen(text[i+1]);
					Debug(DEBUG_BYTE_XML, "split str: '%s', new len = %d", buffer, offset);
					
					if (offset < sizeof(buffer)){
					
						Format(buffer, sizeof(buffer), "%s%s%s", buffer, search, text[i+1]);
						strcopy(text, size, buffer);
						text_len = strlen(text);
						Debug(DEBUG_BYTE_XML, "builded str: '%s'", text);
						g_XMLFixCount++;
					}	
					else
						Debug(DEBUG_BYTE_XML, "new len out of range: %d/%d!", offset, sizeof(buffer));
					break;
				}
				else if (offset == (search_len - 1))
					Debug(DEBUG_BYTE_XML, "skip: validate str", i);
			}
		}
	}
	// TODO: проверить кол-во получаемых значений дл§ g_XMLFixCount
	g_XMLFixCount += ReplaceString(text, 1023, "<", "&lt;");
	g_XMLFixCount += ReplaceString(text, 1023, ">", "&gt;");
	g_XMLFixCount += ReplaceString(text, 1023, "'", "&apos;");
	g_XMLFixCount += ReplaceString(text, 1023, "\"", "&quot;");
	
	Debug(DEBUG_BYTE_XML, "result: '%s'", text);
}


public void Debug(int BYTE, const char[] format, any ...)
{
	if (DEBUG_BYTES == 0 
	|| !((DEBUG_BYTE_PRINT_SERVER|DEBUG_BYTE_LOG_FILE) & DEBUG_BYTES) 
	|| !(DEBUG_BYTES & BYTE)) 
		return;

	static int len;
	static char tag[24];
	len = strlen(format) + 512;
	char[] myFormattedString = new char[len];
	VFormat(myFormattedString, len, format, 3);

	switch (BYTE){
		case DEBUG_BYTE_FUNC_PARAM:
			tag = g_Debug[DEBUG_TAG_FUNC_PARAM];
		case DEBUG_BYTE_METHODMAP:
			tag = g_Debug[DEBUG_TAG_METHODMAP];
		case DEBUG_BYTE_BRACKET:
			tag = g_Debug[DEBUG_TAG_BRACKET];
		case DEBUG_BYTE_COMMENTARY:
			tag = g_Debug[DEBUG_TAG_COMMENTARY];
		case DEBUG_BYTE_XML:
			tag = g_Debug[DEBUG_TAG_XML];
		case DEBUG_BYTE_ERROR:
			tag = g_Debug[DEBUG_TAG_ERROR];
		default:
			tag = g_Debug[DEBUG_TAG_COMMOM];
	}

	Format(myFormattedString, len, "[%s] %s", tag, myFormattedString);
	
	if ((DEBUG_BYTES & DEBUG_BYTE_LOG_FILE))
		LogToFile(DEBUG, myFormattedString);
	
	if ((DEBUG_BYTES & DEBUG_BYTE_PRINT_SERVER))
		PrintToServer(myFormattedString);
}