![Docs screenshot](https://github.com/raziEiL/SourceMod-Npp-Docs/blob/master/img/docs.png "Inline docs")
# SourceMod-Npp-Docs
[![GitHub release](https://img.shields.io/github/release/raziEiL/SourceMod-Npp-Docs.svg?colorB=97CA00?label=version)](https://github.com/raziEiL/SourceMod-Npp-Docs/releases/latest)
[![Donate](https://img.shields.io/badge/Donate-PayPal-green.svg)](https://www.paypal.me/razicat)   
Here the new API docs with all (I hope) function, define, enum, methodmap and fixed xml structure. Docs were generated by reworked generator plugin.

# Plugin

### Features:
 - Generate auto-completion files.
 - Generate inline docs (*sourcemod.xml*).
 - Supports SourceMod 1.7 API specifics.
 
### New in v1.2:
 - Added better way to detect commentary.
 - Added methods docs (*Still in progress...*).
 - Added more console stats.
 - Added xml filter.
 - Code optimization.
 - Detect all func params.
 - Detect enum & define correctly.
 - Detect methodmap selection.
 - Makes keywords to pop up correctly.

 
### Server command:
**sm_makedocs** - starts to parse SourceMod includes and generates output files.

# Notepad++
**SourceMod docs** files are located in the **plugins\NPP\\** subfolder of sourcemod folder.  
**Notepad++ API** files are located in the **plugins\APIs\\** subfolder of the Notepad++ installation folder.

>**Note:** Use **sm_makedocs** command to generate docs or get them from the [latest release](https://github.com/raziEiL/SourceMod-Npp-Docs/releases/latest)).

## Highlights
If you are too lazy to configure your own style go to **SourceMod docs** folder and copy **userDefineLang.xml** to **<USER_NAME>\AppData\Roaming\Notepad++\\**  
If you want to configurate it or update keyword check **plugins\NPP\\** folder for **NPP_STYLE** files. These files contain defining the keyword lists for the SourcePawn language. Open one of those files, select keywords and copy. Go to **Notepd++ -> Lanuguage -> Define your language...** Select you own language or create new and past keywords to the Keywords Lists group. Do it for other groups too. More information here: [UDL 2.0](https://udl20.weebly.com/index.html). 

>**Note:** Define your language as **sourcemod**

## Autocompletion
Copy **sourcemod.xml** file from **SourceMod docs** folder to **Notepad++ API** folder. Done! The completion list can be triggered automatically as you type, via settings in **Settings -> Preferences -> Auto-Completion:** Auto-Completion is enabled by a checkbox. Additionally there is a setting "From X th character", accepting a the minimum length of a prefix needed before the completion list is shown (some people like 2, some 3, some 4...); and, there is a setting to specify which candidates should be used: words, functions, or both.
>**Note:** Autocompletion supports only **case-sensitive** input! (Due to Notepad++ issue, **case-insensitive** input makes docs pop up incorrectly).

# Methodmap notes
![Docs screenshot](https://github.com/raziEiL/SourceMod-Npp-Docs/blob/master/img/docs%20list.png "Inline docs: methodmap strings")  
These strings are not exist SourceMod function! Purpose of these strings provide access to docs and show methodmap structure. Notepad++ don't reacts on dots in names (exp: fileArray.GetString) and docs not shown, so `.` were separated with `_` symbol.
>**Note:** If you want to use string as code you must remove prefix and separate `_` with `.`  
>**Note:** If you want to watch docs you must do the vice versa.

## Prefix structure:

| MM (Methodmap) type | With tag | Without tag |
|------| ------ | ------ |
| C (Constructor) | MM_`%1`_`%2`\_C\_`%3` | MM_`%1`\_C_`%3` |
| M (Method) | MM_`%1`_`%2`_M\_`%3` | MM_`%1`\_M_`%3` |
| P (Property) | MM_`%1`_`%2`_P\_`%3` | MM_`%1`_P\_`%3` |

Where: `%1` - Class name, `%2` - Tag name, `%3` - Real method/property/constructor name.
>**Note:** **Prefix** - a string before `%3` param (e.g., `MM_ArrayList_Handle_M_`GetArray).

## Examples:

| MM (Methodmap) type | With tag                   | Without tag                |
|---------------------|----------------------------|----------------------------|
| C (Constructor)     | MM_Menu_Handle_C_Menu      | Always has the tag         |
| M (Method)          | MM_Menu_Handle_M_ToPanel   | MM_AdminId_M_BindIdentity  |
| P (Property)        | MM_Menu_Handle_P_ItemCount | MM_AdminId_P_ImmunityLevel |

**Editing string to watch docs:**  
Method: ToPanel()  
Prefix: MM_Menu_Handle_M_  
Result: MM_Menu_Handle_M_ToPanel

**Editing string to use as code:**  
Docs string: MM_AdminId_P_ImmunityLevel  
Removes prefix: MM_AdminId_M_  
Result: my_code.ImmunityLevel() 

# Credits:
 - Thanks [@MCPAN](https://forums.alliedmods.net/member.php?u=73370) for original plugin.
 
# Donation
My cat wants a new toy! I try to make quality and beautiful toys for my beloved cat. I create toys in my spare time but sometimes I can step into a tangle and get confused! Oops! It takes time to get out! When the toy is ready I give it to the cat, the GitHub cat and the community can also play with it. So if you enjoy my toys and want to thank me for my work, you can send any amount. All money will be spent on milk! [Donate :feet:](https://www.paypal.me/razicat)
