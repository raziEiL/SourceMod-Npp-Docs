#define PLUGIN_VERSION "1.3.0"

#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <profiler>

//-----------------------------------
// Pre-compiler option
//-----------------------------------
#define DEBUG_BITS 0//(DEBUG_BIT_LOG|DEBUG_BIT_ERROR|DEBUG_BIT_COMMON|DEBUG_BIT_COMMENTARY)
#define ADD_NPP_STYLE_METHODMAP 1 // write to NPP_STYLE_FUNCTION file all strings but fake methodmaps (e.g., MM_ArrayList_Handle_M_GetArray)
#define ADD_DOCS_OPERATORS_MISC 1
#define ADD_DOCS_VARIABLES		1
#define CASE_SENSITIVE_SORTING	true
#define USE_SHORT_PREFIX		1
#define IGNORE_CASE				"yes"
// -----------------------------------

// bits
enum (<<= 1)
{
	DEBUG_BIT_COMMON = 1,
	DEBUG_BIT_FUNC_PARAM,
	DEBUG_BIT_METHODMAP,
	DEBUG_BIT_BRACKET,
	DEBUG_BIT_COMMENTARY,
	DEBUG_BIT_XML,
	DEBUG_BIT_ERROR,
	// <- adds new bit here
	DEBUG_BIT_PRINT,
	DEBUG_BIT_LOG,
	DEBUG_BIT_ALL = 510
}

enum (<<= 1)
{
	PROP_BIT_GET = 1,
	PROP_BIT_SET
}

enum ()
{
	DEBUG_TAG_COMMOM,
	DEBUG_TAG_FUNC_PARAM,
	DEBUG_TAG_METHODMAP,
	DEBUG_TAG_BRACKET,
	DEBUG_TAG_COMMENTARY,
	DEBUG_TAG_XML,
	DEBUG_TAG_ERROR,
	DEBUG_TOTAL
}

enum ()
{
	PREFIX_METHODMAP,
	PREFIX_METHOD,
	PREFIX_CONSTRUCTOR,
	PREFIX_PROP,
	PREFIX_TOTAL
}

enum ()
{
	COMMENT_PARAM,
	COMMENT_NOTES,
	COMMENT_ERROR,
	COMMENT_RETURN,
	COMMENT_TOTAL
}

enum (<<= 1)
{
	READSTRING_BIT_INVALID = 1,
	READSTRING_BIT_VALID,
	READSTRING_BIT_BUFFER,
	READSTRING_BIT_INLINE,
	READSTRING_BIT_LAST
}

#define	MAX_WIDTH				28
#define WIDTH					MAX_WIDTH - 4
#define SPACE_CHAR				' '
#define SPACE_X4				"    "
#define SPACE_X8				"        "
#define SPACE_X12				"            "
#define SPACE_X16				"                "
#define SPACE_X28				"                            "
#define TEXT_PARAM				"@param"
#define TEXT_RETURN				"@return"
#define TEXT_NORETURN			"@noreturn"
#define TEXT_ERROR				"@error"
#define PATH_INCLUDE			"addons/sourcemod/scripting/include"
#define FILE_SOURCEMOD			"addons/sourcemod/plugins/NPP/sourcemod.xml"
#define FILE_OPERATORS			"addons/sourcemod/plugins/NPP/NPP_STYLE_OPERATORS.sp"
#define FILE_FUNCTIONS			"addons/sourcemod/plugins/NPP/NPP_STYLE_FUNCTION.sp"
#define FILE_CONSTANT			"addons/sourcemod/plugins/NPP/NPP_STYLE_CONSTANT.sp"
#define FILE_MISC				"addons/sourcemod/plugins/NPP/NPP_STYLE_MISC.sp"
// ( ) [ ] ; , - style separator
#define NPP_STYLE_OPERATORS		"( ) [ ] ; , * / % + - << >> >>> < > <= >= == != & && ^ | || ? : = += -= *= /= %= &= ^= |= <<= >>= >>>= ++ -- ~ !"
#define NPP_STYLE_OPERATORS_MISC "for if else do while switch case default return break delete continue new decl public stock const enum forward static funcenum functag native sizeof view_as true false union function methodmap typedef property struct this null typeset"
#define NPP_STYLE_VARIABLES		"bool char int float Handle"
#define LOG						"logs\\npp-generator.log"

public Plugin myinfo =
{
	name = "Npp-generator",
	author = "MCPAN (mcpan@foxmail.com), raziEiL [disawar1]",
	description = "Generate auto-completion files & sourcemod.xml docs",
	version = PLUGIN_VERSION,
	url = "https://github.com/raziEiL/SourceMod-Npp-Docs"
}

char	g_Debug[DEBUG_TOTAL][] = {"COMMON", "FUNC PARAM", "METHODMAP", "BRACKET", "COMMENTARY", "XML", "ERROR"},
		g_FuncPrefix[][] = {"forward", "native", "stock", "public native", "property", "public"},
		g_CommentType[COMMENT_TOTAL][] = {"Params:", "Notes:", "Error:", "Return:"},
		g_ConstSMVars[][] = {"NULL_VECTOR", "NULL_STRING", "MaxClients"},
		DEBUG[PLATFORM_MAX_PATH], g_MethodmapName[48], g_MethodmapTag[48];

#if USE_SHORT_PREFIX
char g_Prefix[PREFIX_TOTAL][] = {"MM_", "M", "C", "P"};
#else
char g_Prefix[PREFIX_TOTAL][] = {"METHODMAP_", "METHOD", "CONSTRUCTOR", "PROP"};
#endif

File g_FileDebug, g_FileSourcemodXML;
StringMap g_FuncTrie, g_Property;
ArrayList g_FuncArray, g_ConstArray, g_MiscArray; // Class ,tag, vars
int g_XMLFixCount;

public void OnPluginStart()
{
	BuildPath(Path_SM, DEBUG, PLATFORM_MAX_PATH, LOG);
	RegServerCmd("sm_makedocs", Cmd_Start, "starts to parse SourceMod includes and generates output files");
}

public Action Cmd_Start(int argc)
{
	PrintToServer("> starts to parse includes! (debug bytes = %d)", DEBUG_BITS);

#if (DEBUG_BITS & DEBUG_BIT_LOG)
	g_FileDebug = OpenFile(DEBUG, "wb");
#endif

	Debug(DEBUG_BIT_COMMON, "--------------------------------------------");
	g_XMLFixCount = 0;
	Handle prof = CreateProfiler();
	StartProfiling(prof);
	CreateDirectory("addons/sourcemod/plugins/NPP", 511);

	int i, size, count[3];
	char buffer[PLATFORM_MAX_PATH];
	ArrayList fileArray = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH)), g_CommonArray = CreateArray(ByteCountToCells(64));

	g_Property = CreateTrie();
	g_FuncTrie = CreateTrie();
	g_FuncArray = CreateArray(ByteCountToCells(64));
	g_ConstArray = CreateArray(ByteCountToCells(64));
	g_MiscArray = CreateArray(ByteCountToCells(64));

	Debug(DEBUG_BIT_COMMON, "> --------------------------------");
	Debug(DEBUG_BIT_COMMON, "> PARSING STARTED");
	Debug(DEBUG_BIT_COMMON, "> --------------------------------");
	Debug(DEBUG_BIT_COMMON, "> I. ADD IN ARRAY");
	Debug(DEBUG_BIT_COMMON, "> --------------------------------");

	if ((size = ReadDirFileList(fileArray, PATH_INCLUDE, "inc")))
	{
		for (i = 0; i < size; i++)
		{
			fileArray.GetString(i, buffer, PLATFORM_MAX_PATH-1);
			ReadIncludeFile(buffer, i);
		}
	}

	Debug(DEBUG_BIT_COMMON, "> --------------------------------");
	Debug(DEBUG_BIT_COMMON, "> II. SORT ARRAY AND WRITE");
	Debug(DEBUG_BIT_COMMON, "> --------------------------------");

	SortADTArrayCustom(g_FuncArray, SortFuncADTArray);
	File file = OpenFile(FILE_FUNCTIONS, "wb");
	g_FileSourcemodXML = OpenFile(FILE_SOURCEMOD, "wb");

	g_FileSourcemodXML.WriteLine("<?xml version=\"1.0\" encoding=\"Windows-1252\" ?>");
	g_FileSourcemodXML.WriteLine("<NotepadPlus>");
	g_FileSourcemodXML.WriteLine("%s<AutoComplete language=\"sourcemod\">", SPACE_X4);
	g_FileSourcemodXML.WriteLine("%s<Environment ignoreCase=\"%s\"/>", SPACE_X4, IGNORE_CASE);

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
			if (ADD_NPP_STYLE_METHODMAP && StrContains(funcname, g_Prefix[PREFIX_METHODMAP]) != -1)
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

	for (i = 0; i < sizeof(g_ConstSMVars); i++)
	{
		if (FindStringInArray(g_ConstArray, g_ConstSMVars[i]) == -1)
			PushArrayString(g_ConstArray, g_ConstSMVars[i]);
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
			if (buffer[0])
				g_FileSourcemodXML.WriteLine("%s<KeyWord name=\"%s\"/>", SPACE_X8, buffer);
		}
	}

	g_FileSourcemodXML.WriteLine("%s</AutoComplete>", SPACE_X4);
	g_FileSourcemodXML.WriteLine("</NotepadPlus>");

	delete file;
	delete fileArray;
	delete g_FuncTrie;
	delete g_Property;
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
	delete g_FileDebug;

	StopProfiling(prof);
	PrintToServer("> Job Done!\n> Time used: %.2fs. / XML error fixed: %d\n> Totally generated: function: %d, misc %d, define %d", GetProfilerTime(prof), g_XMLFixCount, count[0], count[1], count[2]);
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
	bool found_params, found_return, found_error, found_func, found_property, in_property;
	char temp[1024], buffer[1024], funcprefix[14], retval[32], funcname[128], funcnameBak[128], funcparam[32], lastPropName[128], retval2[32];

	ArrayList array_comment[COMMENT_TOTAL];
	for (int elem = 0; elem < COMMENT_TOTAL; elem++)
		array_comment[elem] = CreateArray(ByteCountToCells(1024));

	bool isMethodmap, diveInDeep;
	int comment_byte, nextDeep, propDeep, currentDeep, commentDeep, tempVal, tempVal2;
	Debug(DEBUG_BIT_COMMON, "----- NEW FILE ------");
	Debug(DEBUG_BIT_COMMON, "ReadIncludeFile(PATH=%s, fileIndex=%d, search=%s)", filepath, fileArrayIdx, search);

	ReadString("", 0, true);

	while (ReadFileLine(file, buffer, 1023))
	{
		Debug(DEBUG_BIT_COMMON, "----- new line ------");
		comment_byte = ReadString(buffer, 1023);

		if (comment_byte & READSTRING_BIT_INVALID)
		{
			continue;
		}
		else if ((comment_byte & READSTRING_BIT_LAST) && (comment_byte & (READSTRING_BIT_BUFFER|READSTRING_BIT_INLINE)))
		{
			found_params = false;
			found_return = false;
			found_error = false;

			for (i = 0; i < COMMENT_TOTAL; i++)
				ClearArray(array_comment[i]);

			Debug(DEBUG_BIT_COMMENTARY, "clear all comments");

			commentDeep = nextDeep;
		}

		Debug(DEBUG_BIT_COMMENTARY, "'%s' byte=%d, %s, Buffer: %d, Inline: %d, Last was comment: %d", buffer,comment_byte, READSTRING_BIT_INVALID & comment_byte ? "Invalid" : "Valid", (READSTRING_BIT_BUFFER & comment_byte) != 0, (READSTRING_BIT_INLINE & comment_byte) != 0, (READSTRING_BIT_LAST & comment_byte) != 0 );

		diveInDeep = false;

		if (!(comment_byte & (READSTRING_BIT_BUFFER|READSTRING_BIT_INLINE))){

			tempVal = CountCharInString(buffer, '{');
			tempVal2 = CountCharInString(buffer, '}');

			diveInDeep = tempVal > tempVal2;
			nextDeep += tempVal - tempVal2;
			currentDeep = nextDeep - (diveInDeep ? 1 : 0);
			Debug(DEBUG_BIT_BRACKET, "%d - current, %d - next", currentDeep, nextDeep);

			// check if in methodmap selection

			if (!isMethodmap){

				strcopy(funcprefix, 10, buffer);
				TrimString(funcprefix);

				if (strcmp(funcprefix, "methodmap") == 0 && ReadMethodmapHeader(buffer)){
					isMethodmap = true;

					continue;
				}
			}
			else if (nextDeep <= 0){
				isMethodmap = false;
			}

			if (found_property){

				if (nextDeep <= propDeep){
					found_property = in_property = false;
					Debug(DEBUG_BIT_BRACKET, "prop brackets ended");
				}
				else {
					in_property = true;
				}
			}
		}

		if (comment_byte & (READSTRING_BIT_BUFFER|READSTRING_BIT_INLINE))
		{
			if (!search[0])
			{
				Debug(DEBUG_BIT_COMMENTARY, "skip comment");
				continue;
			}

			if (buffer[0] == '*'/* (value = FindCharInString2(buffer, '*')) != -1 */)
			{
				strcopy(buffer, 1023, buffer[1]);
				//strcopy(buffer, 1023, buffer[++value]);
			}

			TrimString(buffer);

			if (!buffer[0])
			{
				continue;
			}

			if (StrContains(buffer, TEXT_PARAM) == -1 &&
				StrContains(buffer, TEXT_RETURN) == -1 &&
				StrContains(buffer, TEXT_NORETURN) == -1 &&
				StrContains(buffer, TEXT_ERROR) == -1)
			{
				Debug(DEBUG_BIT_COMMENTARY, "'%s'", buffer);
				if (found_params)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X28, buffer);
					PushArrayString(array_comment[COMMENT_PARAM], temp);
				}
				else if (found_return)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_comment[COMMENT_RETURN], temp);
				}
				else if (found_error)
				{
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_comment[COMMENT_ERROR], temp);
				}
				else
				{
					ReplaceString(buffer, 1023, "@note", "");
					ReplaceString(buffer, 1023, "@brief", "");

					TrimString(buffer);
					FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
					PushArrayString(array_comment[COMMENT_NOTES], temp);
				}
			}
			else if ((value = StrContains(buffer, TEXT_PARAM)) != -1)
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
					PushArrayString(array_comment[COMMENT_PARAM], temp);
				}
			}
			else if ((value = StrContains(buffer, TEXT_RETURN)) != -1 || StrContains(buffer, TEXT_NORETURN) != -1)
			{
				found_params = false;
				found_return = true;
				found_error = false;

				if (StrContains(buffer, TEXT_NORETURN) != -1)
				{
					found_return = false;
					continue;
				}

				strcopy(buffer, 1023, buffer[value+7]);
				TrimString(buffer);
				FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
				PushArrayString(array_comment[COMMENT_RETURN], temp);
			}
			else if ((value = StrContains(buffer, TEXT_ERROR)) != -1)
			{
				found_params = false;
				found_return = false;
				found_error = true;
				strcopy(buffer, 1023, buffer[value+6]);
				TrimString(buffer);
				FormatEx(temp, 1023, "%s%s", SPACE_X4, buffer);
				PushArrayString(array_comment[COMMENT_ERROR], temp);
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
					//FindCharInString2(buffer, '(') != -1 || // adds define like: FCVAR_UNREGISTERED     (1<<0)
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
			else if ((value = IsEnumString(buffer)) != -1)
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
						if (ReadString(buffer, 1023) & (READSTRING_BIT_INVALID|READSTRING_BIT_BUFFER|READSTRING_BIT_INLINE))
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
									if (ReadString(buffer, 1023) & (READSTRING_BIT_INVALID|READSTRING_BIT_BUFFER|READSTRING_BIT_INLINE))
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
						Debug(DEBUG_BIT_COMMON, "Ffound: funcprefix='%s' funcname='%s'", funcprefix, buffer);
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

						retval2[0] = 0;

						if (isMethodmap){

							Debug(DEBUG_BIT_COMMON, "%s", funcname);

							if (found_property)
								temp = g_Prefix[PREFIX_PROP];
							else if (!retval[0]){
								temp = g_Prefix[PREFIX_CONSTRUCTOR];
								if (g_MethodmapTag[0])
									strcopy(retval2, sizeof(retval2), g_MethodmapTag);
							}
							else
								temp = g_Prefix[PREFIX_METHOD];

							strcopy(funcnameBak, sizeof(funcnameBak), funcname);

							if (g_MethodmapTag[0])
								Format(temp, 128, "%s%s_%s_%s_", g_Prefix[PREFIX_METHODMAP], g_MethodmapName, g_MethodmapTag, temp);
							else
								Format(temp, 128, "%s%s_%s_", g_Prefix[PREFIX_METHODMAP], g_MethodmapName, temp);

							Format(funcname, 128, "%s%s", temp, funcname);

							Debug(DEBUG_BIT_COMMON, "Ftype:Methodmap: %s", funcname);

							if (!in_property)
								lastPropName = funcname;
							else {
								i = 0;
								GetTrieValue(g_Property, lastPropName, i);

								if (strcmp(funcnameBak, "get") == 0)
									i |= PROP_BIT_GET;
								else if (strcmp(funcnameBak, "set") == 0)
									i |= PROP_BIT_SET;

								SetTrieValue(g_Property, lastPropName, i);
								Debug(DEBUG_BIT_COMMON, "Set lastprop get/set byte: val=%d, '%s'", i, lastPropName);
								continue;
							}
						}
						else
							Debug(DEBUG_BIT_COMMON, "Ftype:Normal: funcname='%s', retval='%s' ", funcname, retval[0] ? retval : (retval2[0] ? retval2 : "void"));

						if (search[0])
						{
							if (strcmp(funcname, search) == 0)
							{

								WriteFileLine(g_FileSourcemodXML, "%s<KeyWord name=\"%s\" func=\"yes\">", SPACE_X8, funcname);
								WriteFileLine(g_FileSourcemodXML, "%s<Overload retVal=\"%s %s\" descr=\"", SPACE_X12, funcprefix, retval[0] ? retval : (retval2[0] ? retval2 : "void"));

								if (IsValidString(retval) && FindStringInArray(g_MiscArray, retval) == -1)
								{
									PushArrayString(g_MiscArray, retval);
								}

								Debug(DEBUG_BIT_BRACKET, "currentDeep=%d, commentDeep=%d", currentDeep, commentDeep);

								if (isMethodmap){

									WriteFileLine(g_FileSourcemodXML, "Methodmap notes:");
									WriteFileLine(g_FileSourcemodXML, "%sThis string is not a real Sourcemod Function!\n%sTo use function remove the '%s' prefix\n%sRead more here: https://github.com/raziEiL/SourceMod-Npp-Docs", SPACE_X4, SPACE_X4, temp, SPACE_X4);

									Debug(DEBUG_BIT_COMMON, "trie search: '%s', result=%d", funcname, GetTrieValue(g_Property, funcname, i));

									if (GetTrieValue(g_Property, funcname, i)){

										WriteFileLine(g_FileSourcemodXML, "Property methods:");

										if (i){
											if (i & PROP_BIT_GET)
												WriteFileLine(g_FileSourcemodXML, "%sHas getter", SPACE_X4);
											if (i & PROP_BIT_SET)
												WriteFileLine(g_FileSourcemodXML, "%sHas setter", SPACE_X4);
										}
										else
											WriteFileLine(g_FileSourcemodXML, "%sNone", SPACE_X4);
									}
								}

								if (currentDeep == commentDeep)
								{
									for (int comment = 0; comment < COMMENT_TOTAL; comment++){

										if ((value = GetArraySize(array_comment[comment])))
										{
											WriteFileLine(g_FileSourcemodXML, g_CommentType[comment]);
											Debug(DEBUG_BIT_COMMENTARY, "comment type: '%s'", g_CommentType[comment]);
											for (i = 0; i < value; i++)
											{
												temp[0] = 0;
												GetArrayString(array_comment[comment], i, temp, 1023);
												ValidateXML(temp, 1023);
												WriteFileLine(g_FileSourcemodXML, temp);
												Debug(DEBUG_BIT_COMMENTARY, "'%s'", temp);
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
							Debug(DEBUG_BIT_ERROR,"UHM...same func name '%s'", funcname);
					}

					for (i = 0; i < COMMENT_TOTAL; i++)
						ClearArray(array_comment[i]);

				}
			}
		}
	}

	for (i = 0; i < COMMENT_TOTAL; i++)
		CloseHandle(array_comment[i]);

	CloseHandle(file);
}

int ReadString(char[] buffer, int maxlength, bool clear = false)
{
	static int pos, byte;
	static bool comment_start, last_line, c_buffer, comment_buffer;
	comment_start = false;

	if (clear){
		last_line = c_buffer = false;
		return 0;
	}

	ReplaceString(buffer, maxlength, "\t", " ");
	ReplaceString(buffer, maxlength, "\"", "'");
	ReplaceString(buffer, maxlength, "%", "%%");
	TrimString(buffer);

	if (strlen(buffer))
	{
		pos = 0;

		if (!comment_buffer){

			if (buffer[0] == '/' && (buffer[1] == '/' || (c_buffer = comment_buffer = buffer[1] == '*')))
			{
				comment_start = true;
				strcopy(buffer, 1023, buffer[2]);
				Debug(DEBUG_BIT_COMMENTARY, "%s comment: '%s'", comment_buffer ? "block" : "inline" , buffer);

			}
		}

		if (comment_buffer && (pos = StrContains(buffer, "*/")) != -1)
		{
			c_buffer = false;
			buffer[pos] = 0;
			TrimString(buffer);

			Debug(DEBUG_BIT_COMMENTARY, "end of block comment: '%s'", buffer);
		}

		if (!comment_start && !comment_buffer){

			if ((pos = StrContains(buffer, "/*")) != -1 || (pos = StrContains(buffer, "//")) != -1)
				buffer[pos] = 0;
		}
		//else if (comment_buffer)
		//	Debug(DEBUG_BIT_COMMENTARY, "in block comment: '%s'", buffer);

		TrimString(buffer);
	}

	byte = strlen(buffer) ? READSTRING_BIT_VALID : READSTRING_BIT_INVALID;

	if (comment_buffer)
		byte |= READSTRING_BIT_BUFFER;
	else if (comment_start)
		byte |= READSTRING_BIT_INLINE;

	if (last_line)
		byte |= READSTRING_BIT_LAST;

	if (!(byte & READSTRING_BIT_INLINE) && !(byte & READSTRING_BIT_BUFFER))
		last_line = true;
	else if ((byte & READSTRING_BIT_INLINE) || (byte & READSTRING_BIT_BUFFER))
		last_line = false;

	comment_buffer = c_buffer;

	return byte;
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

		Debug(DEBUG_BIT_COMMON, "ReadFuncString -> '%s'", funcname);

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

	TrimString(buffer);

	if (buffer[0]){

		static char str[1024];

		str[0] = 0;
		strcopy(str, 10, buffer);

		if (strcmp(str, "methodmap") == 0){

			static int pos;
			str[0] = 0;
			strcopy(str, sizeof(str), buffer);
			strcopy(str, sizeof(str), str[10]);
			ReplaceString(str, sizeof(str), "{", "");
			TrimString(str);

			Debug(DEBUG_BIT_METHODMAP, "methodmap detected! '%s'", buffer);

			if ((pos = FindCharInString2(str, '<')) != -1)
			{
				strcopy(g_MethodmapTag, sizeof(g_MethodmapTag), str[pos+1]);
				strcopy(str, pos, str);
				TrimString(g_MethodmapTag);
				TrimString(str);
				Debug(DEBUG_BIT_METHODMAP, "tag detected! calss='%s', tag='%s'", str, g_MethodmapTag);

				if (IsValidString(g_MethodmapTag)){
					if (FindStringInArray(g_MiscArray, g_MethodmapTag) == -1)
						PushArrayString(g_MiscArray, g_MethodmapTag);
				}
				else
					g_MethodmapTag[0] = 0;
			}
			strcopy(g_MethodmapName, sizeof(g_MethodmapName), str);
			if (IsValidString(g_MethodmapName)){

				if (FindStringInArray(g_MiscArray, g_MethodmapName) == -1)
					PushArrayString(g_MiscArray, g_MethodmapName);

				Debug(DEBUG_BIT_METHODMAP, "success! calss='%s', tag='%s'", g_MethodmapName, g_MethodmapTag);
				return true;
			}
			else {
				g_MethodmapName[0] = 0;
				g_MethodmapTag[0] = 0;
				Debug(DEBUG_BIT_ERROR, "Failed to detect methodmap class/tag. Called from %s", g_Debug[DEBUG_TAG_METHODMAP]);
				return false;
			}
		}
	}
	return false;
}

void WriteFuncParams(Handle handle, char[] buffer, int maxlength, bool isLineBreaked = false)
{
	static char buildStr[2048];
	Format(buildStr, sizeof(buildStr), "%s%s", buildStr, buffer);

	Debug(DEBUG_BIT_FUNC_PARAM, "Split func params (is line breaked=%d):", isLineBreaked);
	Debug(DEBUG_BIT_FUNC_PARAM, "src: '%s'", buildStr);

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

							Debug(DEBUG_BIT_ERROR, "Array index out-of-bounds! No params? Called from %s", g_Debug[DEBUG_TAG_FUNC_PARAM]);
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
					Debug(DEBUG_BIT_FUNC_PARAM, "%d. '%s'", ++count, temp);
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

				if (IsValidString(defines_temp[i]) && FindStringInArray(handle, defines_temp[i]) == -1 && !StrEqual(defines_temp[i], "then") && !StrEqual(defines_temp[i], "and"))
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
	return strcmp(str1, str2, CASE_SENSITIVE_SORTING);
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

int IsEnumString(const char[] buffer)
{
	int pos = StrContains(buffer, "enum");
	
	if (pos != -1){
		int offset = pos + 4;
		if (strlen(buffer) > offset){
			if ((buffer[offset] > 64 && buffer[offset] < 91) || (buffer[offset] > 96 && buffer[offset] < 123))
				return -1;
		}	
		return pos;
	}	
	return pos;
}

void ValidateXML(char[] text, int size)
{
	static char buffer[1024];
	char search[] = "&amp;";

	static int i, offset, text_len, search_len;

	text_len = strlen(text);
	search_len = strlen(search);

	Debug(DEBUG_BIT_XML, "text = '%s', search = '%s'", text, search);

	for (i = 0; i < text_len; i++){

		if (text[i] == search[0]){

			Debug(DEBUG_BIT_XML, "match at pos: %d", i);

			for (offset = 1; offset < search_len; offset++){

				if (i+offset >= size){
					Debug(DEBUG_BIT_XML, "offset out of range: %d/%d!", offset, size);
					break;
				}

				if (text[i+offset] != search[offset]){

					strcopy(buffer, i+1, text);
					offset = strlen(buffer) + strlen(search) + strlen(text[i+1]);
					Debug(DEBUG_BIT_XML, "split str: '%s', new len = %d", buffer, offset);

					if (offset < sizeof(buffer)){

						Format(buffer, sizeof(buffer), "%s%s%s", buffer, search, text[i+1]);
						strcopy(text, size, buffer);
						text_len = strlen(text);
						Debug(DEBUG_BIT_XML, "builded str: '%s'", text);
						g_XMLFixCount++;
					}
					else
						Debug(DEBUG_BIT_XML, "new len out of range: %d/%d!", offset, sizeof(buffer));
					break;
				}
				else if (offset == (search_len - 1))
					Debug(DEBUG_BIT_XML, "skip: validate str", i);
			}
		}
	}

	g_XMLFixCount += ReplaceString(text, 1023, "<", "&lt;");
	g_XMLFixCount += ReplaceString(text, 1023, ">", "&gt;");
	g_XMLFixCount += ReplaceString(text, 1023, "'", "&apos;");
	g_XMLFixCount += ReplaceString(text, 1023, "\"", "&quot;");

	Debug(DEBUG_BIT_XML, "result: '%s'", text);
}

void Debug(int BIT, const char[] format, any ...)
{
	if (DEBUG_BITS == 0
	|| !((DEBUG_BIT_LOG|DEBUG_BIT_PRINT) & DEBUG_BITS)
	|| !(DEBUG_BITS & BIT))
		return;

	static char sData[32], sFormattedStr[2048];

	VFormat(sFormattedStr, sizeof(sFormattedStr), format, 3);
	FormatTime(sData, sizeof(sData), "%m/%d/%Y - %H:%M:%S");
	Format(sFormattedStr, sizeof(sFormattedStr), "%s [%s] %s", sData, g_Debug[GetBitPos(BIT)-1], sFormattedStr);

#if (DEBUG_BITS & DEBUG_BIT_LOG)
	g_FileDebug.WriteLine(sFormattedStr);
#endif
#if (DEBUG_BITS & DEBUG_BIT_PRINT)
	PrintToServer(sFormattedStr);
#endif
}

int GetBitPos(int n)
{
	static int pos;
	pos = 0;

	while (n)
	{
		n >>= 1;
		++pos;
	}

	return pos;
}
