/*
top10hlxce-announce.sp

Plays an announcement when a top10 ranked player of hlstats ce comes into your server.
Uses HLStatsX API instead of direct database access.
*/
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#include <hlstatsx_api>
#define REQUIRE_PLUGIN

#define MAX_SOUNDS 64
#define PLUGIN_VERSION "2.1.1"

int g_Rank[MAXPLAYERS+1] = { -1, ... };
int g_MessageType[MAXPLAYERS+1] = { -1, ... };

ConVar g_cvEnabled;
ConVar g_cvTextType;
ConVar g_cvSoundsFile;

Handle g_hEnableAnnouncementCookie;
Handle g_hPlaySoundCookie;
Handle g_hAnnounceMeCookie;
Handle g_hMessageTypeCookie;

KeyValues g_kvSoundsFile;
int g_iTotalSounds;

bool g_bHLStatsApi = false;
bool g_bStatsRequested[MAXPLAYERS+1] = { false, ... };
bool g_bIsLeft4Dead = false;

public Plugin myinfo = {
	name = "Top 10 HLStatsX CE Announcer",
	author = "Snelvuur, Claude.ai guided by DNA.styx",
	description = "Announces when top 10 ranked HLStatsX players connect",
	version = PLUGIN_VERSION,
	url = "https://github.com/DNA-styx/HLStatsX-Top10-Announcer"
};

public void OnPluginStart()
{
	// Validate game support
	char gameFolder[32];
	GetGameFolderName(gameFolder, sizeof(gameFolder));
	
	char supportedGames[][] = {
		"tf", "dod", "hl2mp", "cstrike", "left4dead", "l4d2"
	};
	
	bool supported = false;
	for (int i = 0; i < sizeof(supportedGames); i++) {
		if (StrEqual(gameFolder, supportedGames[i], false)) {
			supported = true;
			g_bIsLeft4Dead = (i >= 4); // left4dead and l4d2
			break;
		}
	}
	
	if (!supported) {
		SetFailState("Unsupported game: %s", gameFolder);
	}
	
	// Create ConVars
	CreateConVar("sm_top10_hlstatsce_version", PLUGIN_VERSION, 
		"Top10 Announcer Version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	
	g_cvEnabled = CreateConVar("sm_top10_hlstatsce_enabled", "1", 
		"Enable/disable the Top10 announcer plugin", 
		FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	g_cvTextType = CreateConVar("sm_top10_hlstatsce_text", "2", 
		"Message display type: 1=Center, 2=Hint, 3=Chat", 
		FCVAR_NONE, true, 1.0, true, 3.0);
	
	g_cvSoundsFile = CreateConVar("sm_top10_hlstatsce_sounds", 
		"addons/sourcemod/configs/top10_sounds.kv", 
		"Path to sounds configuration file", FCVAR_NONE);
	
	AutoExecConfig(true, "top10_hlstatsce");
	
	// Register cookies
	SetCookieMenuItem(CookieMenuHandler_Top10, 0, "Top10 Announcements");
	
	g_hEnableAnnouncementCookie = RegClientCookie("hlstatsx_top10_joinmsg_enable", 
		"Enable top10 join messages", CookieAccess_Public);
	g_hPlaySoundCookie = RegClientCookie("hlstatsx_top10_joinmsg_sound", 
		"Play sound when top10 player joins", CookieAccess_Public);
	g_hAnnounceMeCookie = RegClientCookie("hlstatsx_top10_announceme", 
		"Announce my rank when I join", CookieAccess_Public);
	g_hMessageTypeCookie = RegClientCookie("hlstatsx_top10_joinmsg_type", 
		"Message display type preference", CookieAccess_Public);
}

public void OnAllPluginsLoaded()
{
	g_bHLStatsApi = LibraryExists("hlstatsx_api");
	
	if (!g_bHLStatsApi) {
		LogError("HLStatsX API plugin (hlstatsx_api.smx) is required but not loaded!");
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "hlstatsx_api")) {
		g_bHLStatsApi = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "hlstatsx_api")) {
		g_bHLStatsApi = false;
	}
}

public void OnPluginEnd()
{
	delete g_kvSoundsFile;
}

public void OnMapStart()
{
	// Skip sound loading for L4D/L4D2
	if (g_bIsLeft4Dead) {
		return;
	}
	
	char path[PLATFORM_MAX_PATH];
	g_cvSoundsFile.GetString(path, sizeof(path));
	
	if (path[0] == '\0' || !FileExists(path)) {
		LogError("Sound config file not found: %s", path);
		return;
	}
	
	// Load sound configuration
	delete g_kvSoundsFile;
	g_kvSoundsFile = new KeyValues("top10_sounds");
	
	if (!FileToKeyValues(g_kvSoundsFile, path)) {
		LogError("Failed to parse sound config: %s", path);
		delete g_kvSoundsFile;
		return;
	}
	
	// Precache and add sounds to downloads
	g_iTotalSounds = 0;
	char key[4], soundPath[PLATFORM_MAX_PATH];
	
	for (int i = 0; i < MAX_SOUNDS; i++) {
		IntToString(i, key, sizeof(key));
		g_kvSoundsFile.GetString(key, soundPath, sizeof(soundPath));
		
		if (soundPath[0] == '\0') {
			break;
		}
		
		PrecacheSound(soundPath, true);
		Format(soundPath, sizeof(soundPath), "sound/%s", soundPath);
		AddFileToDownloadsTable(soundPath);
		g_iTotalSounds++;
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client) || !g_cvEnabled.BoolValue || !g_bHLStatsApi) {
		return;
	}
	
	g_bStatsRequested[client] = false;
	RequestHLStatsRank(client);
}

public void OnClientDisconnect(int client)
{
	g_Rank[client] = -1;
	g_MessageType[client] = -1;
	g_bStatsRequested[client] = false;
}

void RequestHLStatsRank(int client)
{
	if (!IsClientInGame(client) || g_bStatsRequested[client]) {
		return;
	}
	
	bool success = HLStatsX_Api_GetStats("playerinfo", client, HLStatsX_Callback, 0);
	
	if (success) {
		g_bStatsRequested[client] = true;
	} else {
		// Retry after 3 seconds
		CreateTimer(3.0, Timer_RetryRequest, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_RetryRequest(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	
	if (client > 0 && IsClientInGame(client) && !g_bStatsRequested[client]) {
		RequestHLStatsRank(client);
	}
	
	return Plugin_Stop;
}

public void HLStatsX_Callback(int command, int payload, int client, DataPack &datapack)
{
	if (!IsClientInGame(client)) {
		delete datapack;
		return;
	}
	
	DataPack pack = view_as<DataPack>(CloneHandle(datapack));
	
	int rank = pack.ReadCell(); // Player rank (only data we need)
	
	delete datapack;
	delete pack;
	
	g_Rank[client] = rank;
	
	if (AreClientCookiesCached(client)) {
		OnClientCookiesCached(client);
	}
}

public void OnClientCookiesCached(int client)
{
	if (g_Rank[client] < 1 || g_Rank[client] > 10) {
		g_Rank[client] = -1;
		return;
	}
	
	// Check if player wants their rank announced
	char buffer[4];
	GetClientCookie(client, g_hAnnounceMeCookie, buffer, sizeof(buffer));
	
	if (!StrEqual(buffer, "") && !StringToInt(buffer)) {
		return; // Player disabled their announcement
	}
	
	// Build announcement message
	char message[128];
	Format(message, sizeof(message), 
		"Top 10 player %N connected, currently rank %d", client, g_Rank[client]);
	
	// Send to all players who want announcements
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		
		GetClientCookie(i, g_hEnableAnnouncementCookie, buffer, sizeof(buffer));
		
		if (StrEqual(buffer, "") || StringToInt(buffer)) {
			PrintMessage(i, message);
		}
	}
	
	// Play sound if configured
	if (g_kvSoundsFile != null && g_iTotalSounds > 0) {
		PlayTop10Sound();
	}
	
	g_Rank[client] = -1; // Reset after announcement
}

void PlayTop10Sound()
{
	char key[4], sound[PLATFORM_MAX_PATH], buffer[4];
	int soundIndex = GetRandomInt(0, g_iTotalSounds - 1);
	
	IntToString(soundIndex, key, sizeof(key));
	g_kvSoundsFile.GetString(key, sound, sizeof(sound));
	
	if (sound[0] == '\0') {
		return;
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsClientInGame(i)) {
			continue;
		}
		
		GetClientCookie(i, g_hPlaySoundCookie, buffer, sizeof(buffer));
		
		if (StrEqual(buffer, "") || StringToInt(buffer)) {
			EmitSoundToClient(i, sound);
		}
	}
}

void PrintMessage(int client, const char[] text)
{
	int messageType = (g_MessageType[client] != -1) ? 
		g_MessageType[client] : g_cvTextType.IntValue;
	
	switch (messageType) {
		case 1: PrintCenterText(client, text);
		case 2: PrintHintText(client, text);
		case 3: PrintToChat(client, text);
		default: PrintCenterText(client, text);
	}
}

// ========================================================================
// COOKIE MENU SYSTEM
// ========================================================================

public void CookieMenuHandler_Top10(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_SelectOption) {
		ShowPrefMenu(client);
	}
}

void ShowPrefMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Top10);
	menu.SetTitle("Top10 Announcement Settings");
	
	char display[128], cookie[4];
	bool enabled;
	
	// Enable/disable join messages
	GetClientCookie(client, g_hEnableAnnouncementCookie, cookie, sizeof(cookie));
	enabled = StrEqual(cookie, "") || StringToInt(cookie);
	Format(display, sizeof(display), "%s: Join Messages", enabled ? "Disable" : "Enable");
	menu.AddItem(enabled ? "0" : "1", display);
	
	// Enable/disable sounds
	GetClientCookie(client, g_hPlaySoundCookie, cookie, sizeof(cookie));
	enabled = StrEqual(cookie, "") || StringToInt(cookie);
	Format(display, sizeof(display), "%s: Join Sounds", enabled ? "Disable" : "Enable");
	menu.AddItem(enabled ? "0" : "1", display);
	
	// Enable/disable personal announcement
	GetClientCookie(client, g_hAnnounceMeCookie, cookie, sizeof(cookie));
	enabled = StrEqual(cookie, "") || StringToInt(cookie);
	Format(display, sizeof(display), "%s: Announce My Rank", enabled ? "Disable" : "Enable");
	menu.AddItem(enabled ? "0" : "1", display);
	
	// Change message type
	GetClientCookie(client, g_hMessageTypeCookie, cookie, sizeof(cookie));
	int msgType = StrEqual(cookie, "") ? g_cvTextType.IntValue : StringToInt(cookie);
	char msgTypeStr[16];
	switch (msgType) {
		case 1: msgTypeStr = "Center";
		case 2: msgTypeStr = "Hint";
		case 3: msgTypeStr = "Chat";
		default: msgTypeStr = "Center";
	}
	Format(display, sizeof(display), "Message Type: %s", msgTypeStr);
	menu.AddItem("", display);
	
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Top10(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action) {
		case MenuAction_Select: {
			char value[4];
			menu.GetItem(param2, value, sizeof(value));
			
			Handle cookie;
			switch (param2) {
				case 0: cookie = g_hEnableAnnouncementCookie;
				case 1: cookie = g_hPlaySoundCookie;
				case 2: cookie = g_hAnnounceMeCookie;
				case 3: {
					ShowMessageTypeMenu(param1);
					return 0;
				}
				default: {
					ShowPrefMenu(param1);
					return 0;
				}
			}
			
			SetClientCookie(param1, cookie, value);
			ShowPrefMenu(param1);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				ShowCookieMenu(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

void ShowMessageTypeMenu(int client)
{
	Menu menu = new Menu(MenuHandler_MessageType);
	menu.SetTitle("Choose Message Type:");
	menu.AddItem("1", "Center Text");
	menu.AddItem("2", "Hint Text");
	menu.AddItem("3", "Chat Text");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_MessageType(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action) {
		case MenuAction_Select: {
			char value[4];
			menu.GetItem(param2, value, sizeof(value));
			SetClientCookie(param1, g_hMessageTypeCookie, value);
			g_MessageType[param1] = StringToInt(value);
			ShowPrefMenu(param1);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				ShowPrefMenu(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}