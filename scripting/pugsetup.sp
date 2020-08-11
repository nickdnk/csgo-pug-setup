#include <clientprefs>
#include <cstrike>
#include <sdktools>
#include <sourcemod>

#include "include/logdebug.inc"
#include "include/pugsetup.inc"
#include "include/restorecvars.inc"
#include "pugsetup/util.sp"

#undef REQUIRE_EXTENSIONS
#include <SteamWorks>

#undef REQUIRE_PLUGIN

#define ALIAS_LENGTH 64
#define COMMAND_LENGTH 64
#define LIVE_TIMER_INTERVAL 0.3

#pragma semicolon 1
#pragma newdecls required

/***********************
 *                     *
 *   Global variables  *
 *                     *
 ***********************/

/** ConVar handles **/
ConVar g_AdminFlagCvar;
ConVar g_AimMapListCvar;
ConVar g_AllowCustomReadyMessageCvar;
ConVar g_AnnounceCountdownCvar;
ConVar g_AutoRandomizeCaptainsCvar;
ConVar g_AutoSetupCvar;
ConVar g_CvarVersionCvar;
ConVar g_DemoNameFormatCvar;
ConVar g_DemoTimeFormatCvar;
ConVar g_DisplayMapVotesCvar;
ConVar g_DoVoteForSidesRoundDecisionCvar;
ConVar g_EchoReadyMessagesCvar;
ConVar g_ExcludedMaps;
ConVar g_ExcludeSpectatorsCvar;
ConVar g_ForceDefaultsCvar;
ConVar g_InstantRunoffVotingCvar;
ConVar g_LiveCfgCvar;
ConVar g_MapListCvar;
ConVar g_MapVoteTimeCvar;
ConVar g_MaxTeamSizeCvar;
ConVar g_MessagePrefixCvar;
ConVar g_MutualUnpauseCvar;
ConVar g_PausingEnabledCvar;
ConVar g_PostGameCfgCvar;
ConVar g_QuickRestartsCvar;
ConVar g_RandomizeMapOrderCvar;
ConVar g_RandomOptionInMapVoteCvar;
ConVar g_SetupEnabledCvar;
ConVar g_SnakeCaptainsCvar;
ConVar g_UseGameWarmupCvar;
ConVar g_WarmupCfgCvar;
ConVar g_WarmupMoneyOnSpawnCvar;
ConVar g_TeamName1Cvar;
ConVar g_TeamName2Cvar;

/** Setup menu options **/
bool g_DisplayMapType = true;
bool g_DisplayTeamType = true;
bool g_DisplayAutoLive = true;
bool g_DisplaySidesRound = true;
bool g_DisplayFriendlyFire = true;
bool g_DisplayTeamSize = true;
bool g_DisplayRecordDemo = true;
bool g_DisplayMapChange = false;
bool g_DisplayAimWarmup = true;
bool g_DisplayPlayout = false;

/** Setup info **/
int g_Leader = -1;
ArrayList g_MapList;
ArrayList g_PastMaps;
ArrayList g_AimMapList;
bool g_ForceEnded = false;

/** Specific choices made when setting up **/
int g_PlayersPerTeam = 5;
TeamType g_TeamType = TeamType_Captains;
MapType g_MapType = MapType_Vote;
bool g_RecordGameOption = false;
SidesRound g_SidesRound = SidesRound_None;
bool g_AutoLive = true;
bool g_DoAimWarmup = false;
bool g_FriendlyFire = true;
bool g_DoPlayout = false;

/** Other important variables about the state of the game **/
TeamBalancerFunction g_BalancerFunction = INVALID_FUNCTION;
Handle g_BalancerFunctionPlugin = INVALID_HANDLE;

GameState g_GameState = GameState_None;
bool g_SwitchingMaps = false;  // if we're in the middle of a map change
bool g_OnDecidedMap = false;   // whether we're on the map that is going to be used

bool g_Recording = true;
char g_DemoFileName[PLATFORM_MAX_PATH];
bool g_LiveTimerRunning = false;
int g_CountDownTicks = 0;
int g_LiveMessageCount = 8;
bool g_ForceStartSignal = false;

#define CAPTAIN_COMMAND_HINT_TIME 15
#define START_COMMAND_HINT_TIME 15
#define READY_COMMAND_HINT_TIME 19
int g_LastCaptainHintTime = 0;
int g_LastReadyHintTime = 0;

/** Pause information **/
bool g_ctUnpaused = false;
bool g_tUnpaused = false;

/** Custom ready messages **/
Handle g_ReadyMessageCookie = INVALID_HANDLE;

/** Stuff for workshop map/collection cache **/
char g_DataDir[PLATFORM_MAX_PATH];    // directory to leave cache files in
char g_CacheFile[PLATFORM_MAX_PATH];  // filename of the keyvalue cache file
KeyValues g_WorkshopCache;            // keyvalue struct for the cache

/** Chat aliases loaded **/
ArrayList g_ChatAliases;
ArrayList g_ChatAliasesCommands;
ArrayList g_ChatAliasesModes;

/** Permissions **/
StringMap g_PermissionsMap;
ArrayList g_Commands;  // just a list of all known pugsetup commands

/** Map-choosing variables **/
ArrayList g_MapVetoed;
ArrayList g_MapVotePool;

/** Data about team selections **/
int g_capt1 = -1;
int g_capt2 = -1;
int g_Teams[MAXPLAYERS + 1];
bool g_Ready[MAXPLAYERS + 1];
bool g_PlayerAtStart[MAXPLAYERS + 1];

/** Clan tag data **/
#define CLANTAG_LENGTH 16
bool g_SavedClanTag[MAXPLAYERS + 1];
char g_ClanTag[MAXPLAYERS + 1][CLANTAG_LENGTH];

/** Sides round data **/
int g_SidesWinner = -1;
enum SidesDecision {
  SidesDecision_None,
  SidesDecision_Stay,
  SidesDecision_Swap,
};
SidesDecision g_SidesRoundVotes[MAXPLAYERS + 1];
int g_SidesNumVotesNeeded = 0;
int g_SidesMessageCount = 0;

/** Forwards **/
Handle g_OnForceEnd = INVALID_HANDLE;
Handle g_hOnGoingLive = INVALID_HANDLE;
Handle g_hOnHelpCommand = INVALID_HANDLE;
Handle g_hOnKnifeRoundDecision = INVALID_HANDLE;
Handle g_hOnLive = INVALID_HANDLE;
Handle g_hOnLiveCfg = INVALID_HANDLE;
Handle g_hOnLiveCheck = INVALID_HANDLE;
Handle g_hOnMatchOver = INVALID_HANDLE;
Handle g_hOnNotPicked = INVALID_HANDLE;
Handle g_hOnPermissionCheck = INVALID_HANDLE;
Handle g_hOnPlayerAddedToCaptainMenu = INVALID_HANDLE;
Handle g_hOnPostGameCfg = INVALID_HANDLE;
Handle g_hOnReady = INVALID_HANDLE;
Handle g_hOnReadyToStart = INVALID_HANDLE;
Handle g_hOnSetup = INVALID_HANDLE;
Handle g_hOnSetupMenuOpen = INVALID_HANDLE;
Handle g_hOnSetupMenuSelect = INVALID_HANDLE;
Handle g_hOnStartRecording = INVALID_HANDLE;
Handle g_hOnStateChange = INVALID_HANDLE;
Handle g_hOnUnready = INVALID_HANDLE;
Handle g_hOnWarmupCfg = INVALID_HANDLE;

#include "pugsetup/captainpickmenus.sp"
#include "pugsetup/configs.sp"
#include "pugsetup/consolecommands.sp"
#include "pugsetup/instantrunoffvote.sp"
#include "pugsetup/kniferounds.sp"
#include "pugsetup/leadermenus.sp"
#include "pugsetup/liveon3.sp"
#include "pugsetup/maps.sp"
#include "pugsetup/mapveto.sp"
#include "pugsetup/mapvote.sp"
#include "pugsetup/natives.sp"
#include "pugsetup/setupmenus.sp"
#include "pugsetup/steamapi.sp"

/***********************
 *                     *
 * Sourcemod forwards  *
 *                     *
 ***********************/

// clang-format off
public Plugin myinfo = {
    name = "Nyx Custom CS:GO PugSetup",
    author = "splewis (forked by nickdnk)",
    description = "Tools for setting up pugs.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nickdnk/csgo-pug-setup"
};
// clang-format on

public void OnPluginStart() {
  InitDebugLog(DEBUG_CVAR, "pugsetup");
  LoadTranslations("common.phrases");
  LoadTranslations("core.phrases");
  LoadTranslations("pugsetup.phrases");

  /** ConVars **/
  g_AdminFlagCvar = CreateConVar(
      "sm_pugsetup_admin_flag", "b",
      "Admin flag to mark players as having elevated permissions - e.g. can always pause,setup,end the game, etc.");
  g_AimMapListCvar = CreateConVar(
      "sm_pugsetup_maplist_aim_maps", "aim_maps.txt",
      "If using aim map warmup, the maplist file in addons/sourcemod/configs/pugsetup to use. You may also use a workshop collection ID instead of a maplist if you have the SteamWorks extension installed.");
  g_AllowCustomReadyMessageCvar =
      CreateConVar("sm_pugsetup_allow_custom_ready_messages", "1",
                   "Whether users can set custom ready messages saved via a clientprefs cookie");
  g_AnnounceCountdownCvar =
      CreateConVar("sm_pugsetup_announce_countdown_timer", "1",
                   "Whether to announce how long the countdown has left before the lo3 begins.");
  g_AutoRandomizeCaptainsCvar = CreateConVar(
      "sm_pugsetup_auto_randomize_captains", "0",
      "When games are using captains, should they be automatically randomized once? Note you can still manually set them or use .rand/!rand to redo the randomization.");
  g_AutoSetupCvar =
      CreateConVar("sm_pugsetup_autosetup", "0",
                   "Whether a pug is automatically setup using the default setup options or not.");
  g_DemoNameFormatCvar = CreateConVar(
      "sm_pugsetup_demo_name_format", "pug_{TIME}_{MAP}",
      "Naming scheme for demos. You may use {MAP}, {TIME}, and {TEAMSIZE}. Make sure there are no spaces or colons in this.");
  g_DemoTimeFormatCvar = CreateConVar(
      "sm_pugsetup_time_format", "%Y-%m-%d_%H%M",
      "Time format to use when creating demo file names. Don't tweak this unless you know what you're doing! Avoid using spaces or colons.");
  g_DisplayMapVotesCvar =
      CreateConVar("sm_pugsetup_display_map_votes", "1",
                   "Whether votes cast by players will be displayed to everyone");
  g_DoVoteForSidesRoundDecisionCvar = CreateConVar(
      "sm_pugsetup_vote_for_knife_round_decision", "1",
      "If 0, the first player to type .stay/.swap/.t/.ct will decide the round round winner decision - otherwise a majority vote will be used");
  g_EchoReadyMessagesCvar = CreateConVar("sm_pugsetup_echo_ready_messages", "1",
                                         "Whether to print to chat when clients ready/unready.");
  g_ExcludedMaps = CreateConVar(
      "sm_pugsetup_excluded_maps", "0",
      "Number of past maps to exclude from map votes. Setting this to 0 disables this feature.");
  g_ExcludeSpectatorsCvar = CreateConVar(
      "sm_pugsetup_exclude_spectators", "0",
      "Whether to exclude spectators in the ready-up counts. Setting this to 1 will exclude specators from being selected by captains as well.");
  g_ForceDefaultsCvar = CreateConVar(
      "sm_pugsetup_force_defaults", "0",
      "Whether the default setup options are forced as the setup options (note that admins can override them still).");
  g_InstantRunoffVotingCvar = CreateConVar(
      "sm_pugsetup_instant_runoff_voting", "1",
      "If set, map votes will run instant-runoff style where each client selects their top 3 maps in preference order.");
  g_LiveCfgCvar = CreateConVar("sm_pugsetup_live_cfg", "sourcemod/pugsetup/live.cfg",
                               "Config to execute when the game goes live");
  g_MapListCvar = CreateConVar(
      "sm_pugsetup_maplist", "maps.txt",
      "Maplist file in addons/sourcemod/configs/pugsetup to use. You may also use a workshop collection ID instead of a maplist if you have the SteamWorks extension installed.");
  g_MapVoteTimeCvar =
      CreateConVar("sm_pugsetup_mapvote_time", "25",
                   "How long the map vote should last if using map-votes.", _, true, 10.0);
  g_MaxTeamSizeCvar =
      CreateConVar("sm_pugsetup_max_team_size", "5",
                   "Maximum size of a team when selecting team sizes.", _, true, 2.0);
  g_MessagePrefixCvar = CreateConVar(
      "sm_pugsetup_message_prefix", "[{YELLOW}PugSetup{NORMAL}]",
      "The tag applied before plugin messages. If you want no tag, you can set an empty string here.");
  g_MutualUnpauseCvar = CreateConVar(
      "sm_pugsetup_mutual_unpausing", "1",
      "Whether an unpause command requires someone from both teams to fully unpause the match. Note that this forces the pause/unpause commands to be unrestricted (so anyone can use them).");
  g_PausingEnabledCvar =
      CreateConVar("sm_pugsetup_pausing_enabled", "1", "Whether pausing is allowed.");
  g_PostGameCfgCvar =
      CreateConVar("sm_pugsetup_postgame_cfg", "sourcemod/pugsetup/warmup.cfg",
                   "Config to execute after games finish; should be in the csgo/cfg directory.");
  g_QuickRestartsCvar = CreateConVar(
      "sm_pugsetup_quick_restarts", "1",
      "If set to 1, going live won't restart 3 times and will just do a single restart.");
  g_RandomizeMapOrderCvar =
      CreateConVar("sm_pugsetup_randomize_maps", "1",
                   "When maps are shown in the map vote/veto, whether their order is randomized.");
  g_RandomOptionInMapVoteCvar =
      CreateConVar("sm_pugsetup_random_map_vote_option", "1",
                   "Whether option 1 in a mapvote is the random map choice.");
  g_SetupEnabledCvar = CreateConVar("sm_pugsetup_setup_enabled", "1",
                                    "Whether the sm_setup command is enabled");
  g_SnakeCaptainsCvar = CreateConVar(
      "sm_pugsetup_snake_captain_picks", "0",
      "If set to 0: captains pick players in a ABABABAB order. If set to 1, in a ABBAABBA order. If set to 2, in a ABBABABA order. If set to 3, in a ABBABAAB order.");
  g_UseGameWarmupCvar = CreateConVar(
      "sm_pugsetup_use_game_warmup", "1",
      "Whether to use csgo's built-in warmup functionality. The warmup config (sm_pugsetup_warmup_cfg) will be executed regardless of this setting.");
  g_WarmupCfgCvar =
      CreateConVar("sm_pugsetup_warmup_cfg", "sourcemod/pugsetup/warmup.cfg",
                   "Config file to run before/after games; should be in the csgo/cfg directory.");
  g_WarmupMoneyOnSpawnCvar = CreateConVar(
      "sm_pugsetup_money_on_warmup_spawn", "1",
      "Whether clients recieve 16,000 dollars when they spawn. It's recommended you use mp_death_drop_gun 0 in your warmup config if you use this.");

  g_TeamName1Cvar = CreateConVar("sm_pugsetup_team_name_1", "", "The name of team 1.");
  g_TeamName2Cvar = CreateConVar("sm_pugsetup_team_name_2", "", "The name of team 2.");

  /** Create and exec plugin's configuration file **/
  AutoExecConfig(true, "pugsetup", "sourcemod/pugsetup");

  g_CvarVersionCvar =
      CreateConVar("sm_pugsetup_version", PLUGIN_VERSION, "Current pugsetup version",
                   FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
  g_CvarVersionCvar.SetString(PLUGIN_VERSION);

  HookConVarChange(g_MapListCvar, OnMapListChanged);
  HookConVarChange(g_AimMapListCvar, OnAimMapListChanged);

  /** Commands **/
  g_Commands = new ArrayList(COMMAND_LENGTH);
  LoadTranslatedAliases();
  AddPugSetupCommand("ready", Command_Ready, "Marks the client as ready", Permission_All,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("notready", Command_NotReady, "Marks the client as not ready", Permission_All,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("setup", Command_Setup,
                     "Starts pug setup (.ready, .capt commands become avaliable)", Permission_All);
  AddPugSetupCommand("rand", Command_Rand, "Sets random captains", Permission_Captains,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("pause", Command_Pause, "Pauses the game", Permission_All,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("unpause", Command_Unpause, "Unpauses the game", Permission_All,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("endgame", Command_EndGame, "Pre-emptively ends the match", Permission_Leader);
  AddPugSetupCommand("forceend", Command_ForceEnd,
                     "Pre-emptively ends the match, without any confirmation menu",
                     Permission_Leader);
  AddPugSetupCommand("forceready", Command_ForceReady, "Force-readies a player", Permission_Admin,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("leader", Command_Leader, "Sets the pug leader", Permission_Leader);
  AddPugSetupCommand("capt", Command_Capt, "Gives the client a menu to pick captains",
                     Permission_Leader);
  AddPugSetupCommand("stay", Command_Stay,
                     "Elects to stay on the current team after winning a knife round",
                     Permission_All, ChatAlias_WhenSetup);
  AddPugSetupCommand("swap", Command_Swap,
                     "Elects to swap the current teams after winning a knife round", Permission_All,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("t", Command_T, "Elects to start on T side after winning a knife round",
                     Permission_All, ChatAlias_WhenSetup);
  AddPugSetupCommand("ct", Command_Ct, "Elects to start on CT side after winning a knife round",
                     Permission_All, ChatAlias_WhenSetup);
  AddPugSetupCommand("forcestart", Command_ForceStart, "Force starts the game", Permission_Admin,
                     ChatAlias_WhenSetup);
  AddPugSetupCommand("addmap", Command_AddMap, "Adds a map to the current maplist",
                     Permission_Admin);
  AddPugSetupCommand("removemap", Command_RemoveMap, "Removes a map to the current maplist",
                     Permission_Admin);
  AddPugSetupCommand("listpugmaps", Command_ListPugMaps, "Lists the current maplist",
                     Permission_All);
  AddPugSetupCommand("listaimmaps", Command_ListAimMaps, "Lists the current aim maplist",
                     Permission_All);
  AddPugSetupCommand("start", Command_Start, "Starts the game if autolive is disabled",
                     Permission_Leader, ChatAlias_WhenSetup);
  AddPugSetupCommand("addalias", Command_AddAlias,
                     "Adds a pugsetup alias, and saves it to the chatalias.cfg file",
                     Permission_Admin);
  AddPugSetupCommand("removealias", Command_RemoveAlias, "Removes a pugsetup alias",
                     Permission_Admin);
  AddPugSetupCommand("setdefault", Command_SetDefault, "Sets a default setup option",
                     Permission_Admin);
  AddPugSetupCommand("setdisplay", Command_SetDisplay,
                     "Sets whether a setup option will be displayed", Permission_Admin);
  AddPugSetupCommand("readymessage", Command_ReadyMessage, "Sets your ready message",
                     Permission_All);
  LoadExtraAliases();

  RegConsoleCmd("pugstatus", Command_Pugstatus, "Dumps information about the pug game status");
  RegConsoleCmd("pugsetup_status", Command_Pugstatus,
                "Dumps information about the pug game status");
  RegConsoleCmd("pugsetup_permissions", Command_ShowPermissions,
                "Dumps pugsetup command permissions");
  RegConsoleCmd("pugsetup_chataliases", Command_ShowChatAliases,
                "Dumps registered pugsetup chat aliases");

  /** Hooks **/
  HookEvent("cs_win_panel_match", Event_MatchOver);
  HookEvent("round_start", Event_RoundStart);
  HookEvent("round_end", Event_RoundEnd);
  HookEvent("player_spawn", Event_PlayerSpawn);
  HookEvent("server_cvar", Event_CvarChanged, EventHookMode_Pre);
  HookEvent("player_connect", Event_PlayerConnect);
  HookEvent("player_disconnect", Event_PlayerDisconnect);

  g_OnForceEnd = CreateGlobalForward("PugSetup_OnForceEnd", ET_Ignore, Param_Cell);
  g_hOnGoingLive = CreateGlobalForward("PugSetup_OnGoingLive", ET_Ignore);
  g_hOnHelpCommand = CreateGlobalForward("PugSetup_OnHelpCommand", ET_Ignore, Param_Cell,
                                         Param_Cell, Param_Cell, Param_CellByRef);
  g_hOnKnifeRoundDecision =
      CreateGlobalForward("PugSetup_OnKnifeRoundDecision", ET_Ignore, Param_Cell);
  g_hOnLive = CreateGlobalForward("PugSetup_OnLive", ET_Ignore);
  g_hOnLiveCfg = CreateGlobalForward("PugSetup_OnLiveCfgExecuted", ET_Ignore);
  g_hOnLiveCheck =
      CreateGlobalForward("PugSetup_OnReadyToStartCheck", ET_Ignore, Param_Cell, Param_Cell);
  g_hOnMatchOver = CreateGlobalForward("PugSetup_OnMatchOver", ET_Ignore, Param_Cell, Param_String);
  g_hOnNotPicked = CreateGlobalForward("PugSetup_OnNotPicked", ET_Ignore, Param_Cell);
  g_hOnPermissionCheck = CreateGlobalForward("PugSetup_OnPermissionCheck", ET_Ignore, Param_Cell,
                                             Param_String, Param_Cell, Param_CellByRef);
  g_hOnPlayerAddedToCaptainMenu =
      CreateGlobalForward("PugSetup_OnPlayerAddedToCaptainMenu", ET_Ignore, Param_Cell, Param_Cell,
                          Param_String, Param_Cell);
  g_hOnPostGameCfg = CreateGlobalForward("PugSetup_OnPostGameCfgExecuted", ET_Ignore);
  g_hOnReady = CreateGlobalForward("PugSetup_OnReady", ET_Ignore, Param_Cell);
  g_hOnReadyToStart = CreateGlobalForward("PugSetup_OnReadyToStart", ET_Ignore);
  g_hOnSetup = CreateGlobalForward("PugSetup_OnSetup", ET_Ignore, Param_Cell, Param_Cell,
                                   Param_Cell, Param_Cell);
  g_hOnSetupMenuOpen =
      CreateGlobalForward("PugSetup_OnSetupMenuOpen", ET_Event, Param_Cell, Param_Cell, Param_Cell);
  g_hOnSetupMenuSelect = CreateGlobalForward("PugSetup_OnSetupMenuSelect", ET_Ignore, Param_Cell,
                                             Param_Cell, Param_String, Param_Cell);
  g_hOnStartRecording = CreateGlobalForward("PugSetup_OnStartRecording", ET_Ignore, Param_String);
  g_hOnStateChange =
      CreateGlobalForward("PugSetup_OnGameStateChanged", ET_Ignore, Param_Cell, Param_Cell);
  g_hOnUnready = CreateGlobalForward("PugSetup_OnUnready", ET_Ignore, Param_Cell);
  g_hOnWarmupCfg = CreateGlobalForward("PugSetup_OnWarmupCfgExecuted", ET_Ignore);

  g_ReadyMessageCookie =
      RegClientCookie("pugsetup_ready", "Pugsetup ready message", CookieAccess_Protected);

  g_LiveTimerRunning = false;
  ReadSetupOptions();

  g_MapVotePool = new ArrayList(PLATFORM_MAX_PATH);
  g_PastMaps = new ArrayList(PLATFORM_MAX_PATH);

  // Get workshop cache file setup
  BuildPath(Path_SM, g_DataDir, sizeof(g_DataDir), "data/pugsetup");
  if (!DirExists(g_DataDir)) {
    CreateDirectory(g_DataDir, 511);
  }
  Format(g_CacheFile, sizeof(g_CacheFile), "%s/cache.cfg", g_DataDir);

  PrintToServer("|-------------------------------|");
  PrintToServer("|---- Nyx Custom PUG Loaded ----|");
  PrintToServer("|-------------------------------|");
}

static void AddPugSetupCommand(const char[] command, ConCmd callback, const char[] description,
                               Permission p, ChatAliasMode mode = ChatAlias_Always) {
  char smCommandBuffer[64];
  Format(smCommandBuffer, sizeof(smCommandBuffer), "sm_%s", command);
  g_Commands.PushString(smCommandBuffer);
  RegConsoleCmd(smCommandBuffer, callback, description);
  PugSetup_SetPermissions(smCommandBuffer, p);

  char dotCommandBuffer[64];
  Format(dotCommandBuffer, sizeof(dotCommandBuffer), ".%s", command);
  PugSetup_AddChatAlias(dotCommandBuffer, smCommandBuffer, mode);
}

public void OnMapListChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  if (!StrEqual(oldValue, newValue)) {
    FillMapList(g_MapListCvar, g_MapList);
  }
}

public void OnAimMapListChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
  if (!StrEqual(oldValue, newValue)) {
    FillMapList(g_AimMapListCvar, g_AimMapList);
  }
}

public void OnConfigsExecuted() {
  FillMapList(g_MapListCvar, g_MapList);
  FillMapList(g_AimMapListCvar, g_AimMapList);
  ReadPermissions();
}

public bool OnClientConnect(int client, char[] rejectmsg, int maxlen) {
  g_Ready[client] = false;
  g_SavedClanTag[client] = false;
  CheckAutoSetup();
  return true;
}

public void OnClientDisconnect_Post(int client) {
  int numPlayers = 0;
  for (int i = 1; i <= MaxClients; i++)
    if (IsPlayer(i))
      numPlayers++;

  if (numPlayers == 0 && !g_SwitchingMaps && g_AutoSetupCvar.IntValue == 0) {
    EndMatch(true);
  }
}

public void OnMapStart() {
  if (g_SwitchingMaps) {
    g_SwitchingMaps = false;
  }

  g_ForceEnded = false;
  g_MapVetoed = new ArrayList();
  g_Recording = false;
  g_LiveTimerRunning = false;
  g_ForceStartSignal = false;

  // Map init for workshop collection stuff
  g_WorkshopCache = new KeyValues("Workshop");
  g_WorkshopCache.ImportFromFile(g_CacheFile);

  if (g_GameState == GameState_Warmup) {
    ExecWarmupConfigs();
    if (g_UseGameWarmupCvar.IntValue != 0) {
      StartWarmup();
    }
    StartLiveTimer();
  } else {
    g_capt1 = -1;
    g_capt2 = -1;
    g_Leader = -1;
    for (int i = 1; i <= MaxClients; i++) {
      g_Ready[i] = false;
      g_Teams[i] = CS_TEAM_NONE;
    }

    if (g_GameState == GameState_None) {
      StartSetupHint();
    }
  }
}

public void OnMapEnd() {
  CloseHandle(g_MapVetoed);
  g_WorkshopCache.Rewind();
  g_WorkshopCache.ExportToFile(g_CacheFile);
  delete g_WorkshopCache;
}

public bool UsingCaptains() {
  return g_TeamType == TeamType_Captains || g_MapType == MapType_Veto;
}

public Action Timer_CheckReady(Handle timer) {
  if (g_GameState != GameState_Warmup || !g_LiveTimerRunning) {
    g_LiveTimerRunning = false;
    return Plugin_Stop;
  }

  if (g_DoAimWarmup) {
    EnsurePausedWarmup();
  }

  int readyPlayers = 0;
  int totalPlayers = 0;
  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      UpdateClanTag(i);
      int team = GetClientTeam(i);
      if (g_ExcludeSpectatorsCvar.IntValue == 0 || team == CS_TEAM_CT || team == CS_TEAM_T) {
        totalPlayers++;
        if (g_Ready[i]) {
          readyPlayers++;
        }
      }
    }
  }

  if (totalPlayers >= PugSetup_GetPugMaxPlayers()) {
    GiveReadyHints();
  }

  // beware: scary spaghetti code ahead
  if ((readyPlayers == totalPlayers && readyPlayers >= 2 * g_PlayersPerTeam) ||
      g_ForceStartSignal) {
    g_ForceStartSignal = false;

    if (g_OnDecidedMap) {
      if (g_TeamType == TeamType_Captains) {
        if (IsPlayer(g_capt1) && IsPlayer(g_capt2) && g_capt1 != g_capt2) {
          g_LiveTimerRunning = false;
          PrintHintTextToAll("%t\n%t", "ReadyStatusPlayers", readyPlayers, totalPlayers, "ReadyStatusAllReadyPick");
          CreateTimer(1.0, StartPicking, _, TIMER_FLAG_NO_MAPCHANGE);
          return Plugin_Stop;
        } else {
          StatusHint(readyPlayers, totalPlayers);
        }
      } else {
        g_LiveTimerRunning = false;

        if (g_AutoLive) {
          PrintHintTextToAll("%t\n%t", "ReadyStatusPlayers", readyPlayers, totalPlayers, "ReadyStatusAllReady");
        } else {
          PrintHintTextToAll("%t\n%t", "ReadyStatusPlayers", readyPlayers, totalPlayers, "ReadyStatusAllReadyWaiting");
        }

        ReadyToStart();
        return Plugin_Stop;
      }

    } else {
      if (g_MapType == MapType_Veto) {
        if (IsPlayer(g_capt1) && IsPlayer(g_capt2) && g_capt1 != g_capt2) {
          g_LiveTimerRunning = false;
          PrintHintTextToAll("%t\n%t", "ReadyStatusPlayers", readyPlayers, totalPlayers, "ReadyStatusAllReadyVeto");
          PugSetup_MessageToAll("%t", "VetoMessage");
          CreateTimer(2.0, MapSetup, _, TIMER_FLAG_NO_MAPCHANGE);
          return Plugin_Stop;
        } else {
          StatusHint(readyPlayers, totalPlayers);
        }

      } else {
        g_LiveTimerRunning = false;
        PrintHintTextToAll("%t\n%t", "ReadyStatusPlayers", readyPlayers, totalPlayers, "ReadyStatusAllReadyVote");
        PugSetup_MessageToAll("%t", "VoteMessage");
        CreateTimer(2.0, MapSetup, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
      }
    }

  } else {
    StatusHint(readyPlayers, totalPlayers);
  }

  Call_StartForward(g_hOnLiveCheck);
  Call_PushCell(readyPlayers);
  Call_PushCell(totalPlayers);
  Call_Finish();

  if (g_TeamType == TeamType_Captains && g_AutoRandomizeCaptainsCvar.IntValue != 0 &&
      totalPlayers >= PugSetup_GetPugMaxPlayers()) {
    // re-randomize captains if they aren't set yet
    if (!IsPlayer(g_capt1)) {
      g_capt1 = RandomPlayer();
    }

    while (!IsPlayer(g_capt2) || g_capt1 == g_capt2) {
      if (GetRealClientCount() < 2)
        break;
      g_capt2 = RandomPlayer();
    }
  }

  return Plugin_Continue;
}

public void StatusHint(int readyPlayers, int totalPlayers) {
  char rdyCommand[ALIAS_LENGTH];
  FindAliasFromCommand("sm_ready", rdyCommand);
  bool captainsNeeded = (!g_OnDecidedMap && g_MapType == MapType_Veto) ||
                        (g_OnDecidedMap && g_TeamType == TeamType_Captains);

  if (captainsNeeded) {
    for (int i = 1; i <= MaxClients; i++) {
      if (IsPlayer(i)) {
        GiveCaptainHint(i, readyPlayers, totalPlayers);
      }
    }
  } else {
    PrintHintTextToAll("%t", "ReadyStatus", readyPlayers, totalPlayers, rdyCommand);
  }
}

static void GiveReadyHints() {
  int time = GetTime();
  int dt = time - g_LastReadyHintTime;

  if (dt >= READY_COMMAND_HINT_TIME) {
    g_LastReadyHintTime = time;
    char cmd[ALIAS_LENGTH];
    FindAliasFromCommand("sm_ready", cmd);
    for (int i = 1; i <= MaxClients; i++) {
      if (IsPlayer(i) && !PugSetup_IsReady(i) && OnActiveTeam(i)) {
        PugSetup_Message(i, "%t", "ReadyCommandHint", cmd);
      }
    }
  }
}

static void GiveCaptainHint(int client, int readyPlayers, int totalPlayers) {
  char cap1[MAX_NAME_LENGTH];
  char cap2[MAX_NAME_LENGTH];
  const int kMaxNameLength = 14;

  if (IsPlayer(g_capt1)) {
    Format(cap1, sizeof(cap1), "%N", g_capt1);
    if (strlen(cap1) > kMaxNameLength) {
      strcopy(cap1, kMaxNameLength, cap1);
      Format(cap1, sizeof(cap1), "%s...", cap1);
    }
  } else {
    Format(cap1, sizeof(cap1), "%T", "CaptainNotSelected", client);
  }

  if (IsPlayer(g_capt2)) {
    Format(cap2, sizeof(cap2), "%N", g_capt2);
    if (strlen(cap2) > kMaxNameLength) {
      strcopy(cap2, kMaxNameLength, cap2);
      Format(cap2, sizeof(cap2), "%s...", cap2);
    }
  } else {
    Format(cap2, sizeof(cap2), "%T", "CaptainNotSelected", client);
  }

  char rdyCommand[ALIAS_LENGTH];
  FindAliasFromCommand("sm_ready", rdyCommand);

  PrintHintTextToAll("%t", "ReadyStatusCaptains", readyPlayers, totalPlayers, rdyCommand, cap1, cap2);

  // if there aren't any captains and we full players, print the hint telling the leader how to set
  // captains
  if (!IsPlayer(g_capt1) && !IsPlayer(g_capt2) && totalPlayers >= PugSetup_GetPugMaxPlayers()) {
    // but only do it at most every CAPTAIN_COMMAND_HINT_TIME seconds so it doesn't get spammed
    int time = GetTime();
    int dt = time - g_LastCaptainHintTime;
    if (dt >= CAPTAIN_COMMAND_HINT_TIME) {
      g_LastCaptainHintTime = time;
      char cmd[ALIAS_LENGTH];
      FindAliasFromCommand("sm_capt", cmd);
      PugSetup_MessageToAll("%t", "SetCaptainsHint", PugSetup_GetLeader(), cmd);
    }
  }
}

/***********************
 *                     *
 *     Commands        *
 *                     *
 ***********************/

public bool DoPermissionCheck(int client, const char[] command) {
  Permission p = PugSetup_GetPermissions(command);
  bool result = PugSetup_HasPermissions(client, p);
  char cmd[COMMAND_LENGTH];
  GetCmdArg(0, cmd, sizeof(cmd));
  Call_StartForward(g_hOnPermissionCheck);
  Call_PushCell(client);
  Call_PushString(cmd);
  Call_PushCell(p);
  Call_PushCellRef(result);
  Call_Finish();
  return result;
}

public Action Command_Setup(int client, int args) {
  if (g_SetupEnabledCvar.IntValue == 0) {
    return Plugin_Handled;
  }

  if (g_GameState > GameState_Warmup) {
    PugSetup_Message(client, "%t", "AlreadyLive");
    return Plugin_Handled;
  }

  bool allowedToSetup = DoPermissionCheck(client, "sm_setup");
  if (g_GameState == GameState_None && !allowedToSetup) {
    PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  bool allowedToChangeSetup = PugSetup_HasPermissions(client, Permission_Leader);
  if (g_GameState == GameState_Warmup && !allowedToChangeSetup) {
    PugSetup_GiveSetupMenu(client, true);
    return Plugin_Handled;
  }

  if (IsPlayer(client)) {
    g_Leader = client;
  }

  if (client == 0) {
    // if we did the setup command from the console just use the default settings
    ReadSetupOptions();
    PugSetup_SetupGame(g_TeamType, g_MapType, g_PlayersPerTeam, g_RecordGameOption, g_SidesRound,
                       g_AutoLive, g_FriendlyFire);
  } else {
    PugSetup_GiveSetupMenu(client);
  }

  return Plugin_Handled;
}

public Action Command_Rand(int client, int args) {
  if (g_GameState != GameState_Warmup)
    return Plugin_Handled;

  if (!UsingCaptains()) {
    PugSetup_Message(client, "%t", "NotUsingCaptains");
    return Plugin_Handled;
  }

  if (!DoPermissionCheck(client, "sm_rand")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  PugSetup_SetRandomCaptains();
  return Plugin_Handled;
}

public Action Command_Capt(int client, int args) {
  if (g_GameState != GameState_Warmup)
    return Plugin_Handled;

  if (!UsingCaptains()) {
    PugSetup_Message(client, "%t", "NotUsingCaptains");
    return Plugin_Handled;
  }

  if (!DoPermissionCheck(client, "sm_capt")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char buffer[MAX_NAME_LENGTH];
  if (GetCmdArgs() >= 1) {
    GetCmdArg(1, buffer, sizeof(buffer));
    int target = FindTarget(client, buffer, true, false);
    if (IsPlayer(target))
      PugSetup_SetCaptain(1, target, true);

    if (GetCmdArgs() >= 2) {
      GetCmdArg(2, buffer, sizeof(buffer));
      target = FindTarget(client, buffer, true, false);

      if (IsPlayer(target))
        PugSetup_SetCaptain(2, target, true);

    } else {
      Captain2Menu(client);
    }

  } else {
    Captain1Menu(client);
  }
  return Plugin_Handled;
}

public Action Command_ForceStart(int client, int args) {
  if (g_GameState != GameState_Warmup)
    return Plugin_Handled;

  if (!DoPermissionCheck(client, "sm_forcestart")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i) && !PugSetup_IsReady(i)) {
      PugSetup_ReadyPlayer(i, false);
    }
  }
  g_ForceStartSignal = true;
  return Plugin_Handled;
}

static void ListMapList(int client, ArrayList maplist) {
  int n = maplist.Length;
  if (n == 0) {
    PugSetup_Message(client, "No maps found");
  } else {
    char buffer[PLATFORM_MAX_PATH];
    for (int i = 0; i < n; i++) {
      FormatMapName(maplist, i, buffer, sizeof(buffer));
      PugSetup_Message(client, "Map %d: %s", i + 1, buffer);
    }
  }
}

public Action Command_ListPugMaps(int client, int args) {
  if (!DoPermissionCheck(client, "sm_listpugmaps")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  ListMapList(client, g_MapList);
  return Plugin_Handled;
}

public Action Command_ListAimMaps(int client, int args) {
  if (!DoPermissionCheck(client, "sm_listaimmaps")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  ListMapList(client, g_AimMapList);
  return Plugin_Handled;
}

public Action Command_Start(int client, int args) {
  // Some people like to type .start instead of .setup, since
  // that's often types in ESEA's scrim server setup, so this is allowed here as well.
  if (g_GameState == GameState_None) {
    FakeClientCommand(client, "sm_setup");
    return Plugin_Handled;
  }

  if (g_GameState != GameState_WaitingForStart) {
    return Plugin_Handled;
  }

  if (!DoPermissionCheck(client, "sm_start")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  StartGame();
  return Plugin_Handled;
}

public void LoadTranslatedAliases() {
  // For each of these sm_x commands, we need the
  // translation phrase sm_x_alias to be present.
  AddTranslatedAlias("sm_capt", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_endgame", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_notready", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_pause", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_ready", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_setup");
  AddTranslatedAlias("sm_stay", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_swap", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_unpause", ChatAlias_WhenSetup);
  AddTranslatedAlias("sm_start", ChatAlias_WhenSetup);
}

public void LoadExtraAliases() {
  // Read custom user aliases
  ReadChatConfig();

  // Any extra chat aliases we want
  PugSetup_AddChatAlias(".captain", "sm_capt", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".captains", "sm_capt", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".setcaptains", "sm_capt", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".endmatch", "sm_endgame", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".cancel", "sm_endgame", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".gaben", "sm_ready", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".unready", "sm_notready", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".switch", "sm_swap", ChatAlias_WhenSetup);
  PugSetup_AddChatAlias(".forcestop", "sm_forceend", ChatAlias_WhenSetup);
}

static void AddTranslatedAlias(const char[] command, ChatAliasMode mode = ChatAlias_Always) {
  char translationName[128];
  Format(translationName, sizeof(translationName), "%s_alias", command);

  char alias[ALIAS_LENGTH];
  Format(alias, sizeof(alias), "%T", translationName, LANG_SERVER);

  PugSetup_AddChatAlias(alias, command, mode);
}

public bool FindAliasFromCommand(const char[] command, char alias[ALIAS_LENGTH]) {
  int n = g_ChatAliases.Length;
  char tmpCommand[COMMAND_LENGTH];

  for (int i = 0; i < n; i++) {
    g_ChatAliasesCommands.GetString(i, tmpCommand, sizeof(tmpCommand));

    if (StrEqual(command, tmpCommand)) {
      g_ChatAliases.GetString(i, alias, sizeof(alias));
      return true;
    }
  }

  // If we never found one, just use .<command> since it always gets added by AddPugSetupCommand
  Format(alias, sizeof(alias), ".%s", command);
  return false;
}

public bool FindComandFromAlias(const char[] alias, char command[COMMAND_LENGTH]) {
  int n = g_ChatAliases.Length;
  char tmpAlias[ALIAS_LENGTH];

  for (int i = 0; i < n; i++) {
    g_ChatAliases.GetString(i, tmpAlias, sizeof(tmpAlias));

    if (StrEqual(alias, tmpAlias, false)) {
      g_ChatAliasesCommands.GetString(i, command, sizeof(command));
      return true;
    }
  }

  return false;
}

static bool CheckChatAlias(const char[] alias, const char[] command, const char[] chatCommand,
                           const char[] chatArgs, int client, ChatAliasMode mode) {
  if (StrEqual(chatCommand, alias, false)) {
    if (mode == ChatAlias_WhenSetup && g_GameState == GameState_None) {
      return false;
    }

    // Get the original cmd reply source so it can be restored after the fake client command.
    // This means and ReplyToCommand will go into the chat area, rather than console, since
    // *chat* aliases are for *chat* commands.
    ReplySource replySource = GetCmdReplySource();
    SetCmdReplySource(SM_REPLY_TO_CHAT);
    char fakeCommand[256];
    Format(fakeCommand, sizeof(fakeCommand), "%s %s", command, chatArgs);
    FakeClientCommand(client, fakeCommand);
    SetCmdReplySource(replySource);
    return true;
  }
  return false;
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs) {
  if (!IsPlayer(client))
    return;

  // splits to find the first word to do a chat alias command check
  char chatCommand[COMMAND_LENGTH];
  char chatArgs[255];
  int index = SplitString(sArgs, " ", chatCommand, sizeof(chatCommand));

  if (index == -1) {
    strcopy(chatCommand, sizeof(chatCommand), sArgs);
  } else if (index < strlen(sArgs)) {
    strcopy(chatArgs, sizeof(chatArgs), sArgs[index]);
  }

  if (chatCommand[0]) {
    char alias[ALIAS_LENGTH];
    char cmd[COMMAND_LENGTH];
    for (int i = 0; i < GetArraySize(g_ChatAliases); i++) {
      GetArrayString(g_ChatAliases, i, alias, sizeof(alias));
      GetArrayString(g_ChatAliasesCommands, i, cmd, sizeof(cmd));
      if (CheckChatAlias(alias, cmd, chatCommand, chatArgs, client, g_ChatAliasesModes.Get(i))) {
        break;
      }
    }
  }

  if (StrEqual(sArgs[0], ".help")) {
    const int msgSize = 128;
    ArrayList msgs = new ArrayList(msgSize);

    msgs.PushString("{LIGHT_GREEN}.setup {NORMAL}begins the setup phase");
    msgs.PushString("{LIGHT_GREEN}.endgame {NORMAL}ends the match");
    msgs.PushString("{LIGHT_GREEN}.leader {NORMAL}allows you to set the pug leader");
    msgs.PushString("{LIGHT_GREEN}.capt {NORMAL}allows you to set team captains");
    msgs.PushString("{LIGHT_GREEN}.rand {NORMAL}selects random captains");
    msgs.PushString("{LIGHT_GREEN}.ready/.notready {NORMAL}mark you as ready");
    msgs.PushString("{LIGHT_GREEN}.pause/.unpause {NORMAL}pause the match");

    bool block = false;
    Call_StartForward(g_hOnHelpCommand);
    Call_PushCell(client);
    Call_PushCell(msgs);
    Call_PushCell(msgSize);
    Call_PushCellRef(block);
    Call_Finish();

    if (!block) {
      char msg[msgSize];
      for (int i = 0; i < msgs.Length; i++) {
        msgs.GetString(i, msg, sizeof(msg));
        PugSetup_Message(client, msg);
      }
    }

    delete msgs;
  }

  // Allow using .map as a map-vote revote alias and as a
  // shortcut to the mapchange menu (if avaliable).
  if (StrEqual(sArgs, ".map") || StrEqual(sArgs, "!revote")) {
    if (IsVoteInProgress() && IsClientInVotePool(client)) {
      RedrawClientVoteMenu(client);
    } else if (g_IRVActive) {
      ResetClientVote(client);
      ShowInstantRunoffMapVote(client, 0);
    } else if (PugSetup_IsPugAdmin(client) && g_DisplayMapChange) {
      PugSetup_GiveMapChangeMenu(client);
    }
  }
}

public Action Command_EndGame(int client, int args) {
  if (g_GameState == GameState_None) {
    PugSetup_Message(client, "%t", "NotLiveYet");
  } else {
    if (!DoPermissionCheck(client, "sm_endgame")) {
      if (IsValidClient(client))
        PugSetup_Message(client, "%t", "NoPermission");
      return Plugin_Handled;
    }

    // bypass the menu if console does it
    if (client == 0) {
      Call_StartForward(g_OnForceEnd);
      Call_PushCell(client);
      Call_Finish();

      PugSetup_MessageToAll("%t", "ForceEnd", client);
      EndMatch(true);
      g_ForceEnded = true;
    } else {
      Menu menu = new Menu(MatchEndHandler);
      SetMenuTitle(menu, "%T", "EndMatchMenuTitle", client);
      SetMenuExitButton(menu, true);
      AddMenuBool(menu, false, "%T", "ContinueMatch", client);
      AddMenuBool(menu, true, "%T", "EndMatch", client);
      DisplayMenu(menu, client, 20);
    }
  }
  return Plugin_Handled;
}

public int MatchEndHandler(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    int client = param1;
    bool choice = GetMenuBool(menu, param2);
    if (choice) {
      Call_StartForward(g_OnForceEnd);
      Call_PushCell(client);
      Call_Finish();

      PugSetup_MessageToAll("%t", "ForceEnd", client);
      EndMatch(true);
      g_ForceEnded = true;
    }
  } else if (action == MenuAction_End) {
    CloseHandle(menu);
  }
}

public Action Command_ForceEnd(int client, int args) {
  if (!DoPermissionCheck(client, "sm_forceend")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  Call_StartForward(g_OnForceEnd);
  Call_PushCell(client);
  Call_Finish();

  PugSetup_MessageToAll("%t", "ForceEnd", client);
  EndMatch(true);
  g_ForceEnded = true;
  return Plugin_Handled;
}

public Action Command_ForceReady(int client, int args) {
  if (!DoPermissionCheck(client, "sm_forceready")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char buffer[MAX_NAME_LENGTH];
  if (args >= 1 && GetCmdArg(1, buffer, sizeof(buffer))) {
    if (StrEqual(buffer, "all")) {
      for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
          PugSetup_ReadyPlayer(i);
        }
      }
    } else {
      int target = FindTarget(client, buffer, true, false);
      if (IsPlayer(target)) {
        PugSetup_ReadyPlayer(target);
      }
    }
  } else {
    PugSetup_Message(client, "Usage: .forceready <player>");
  }

  return Plugin_Handled;
}

static bool Pauseable() {
  return g_GameState >= GameState_SidesRound && g_PausingEnabledCvar.IntValue != 0;
}

public Action Command_Pause(int client, int args) {
  if (g_GameState == GameState_None)
    return Plugin_Handled;

  if (!Pauseable() || IsPaused())
    return Plugin_Handled;

  if (g_MutualUnpauseCvar.IntValue != 0) {
    PugSetup_SetPermissions("sm_pause", Permission_All);
  }

  if (!DoPermissionCheck(client, "sm_pause")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  g_ctUnpaused = false;
  g_tUnpaused = false;
  Pause();
  if (IsPlayer(client)) {
    PugSetup_MessageToAll("%t", "Pause", client);
  }

  return Plugin_Handled;
}

public Action Command_Unpause(int client, int args) {
  if (g_GameState == GameState_None)
    return Plugin_Handled;

  if (!IsPaused())
    return Plugin_Handled;

  if (g_MutualUnpauseCvar.IntValue != 0) {
    PugSetup_SetPermissions("sm_unpause", Permission_All);
  }

  if (!DoPermissionCheck(client, "sm_unpause")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char unpauseCmd[ALIAS_LENGTH];
  FindAliasFromCommand("sm_unpause", unpauseCmd);

  if (g_MutualUnpauseCvar.IntValue == 0) {
    Unpause();
    if (IsPlayer(client)) {
      PugSetup_MessageToAll("%t", "Unpause", client);
    }
  } else {
    // Let console force unpause
    if (client == 0) {
      Unpause();
    } else {
      int team = GetClientTeam(client);
      if (team == CS_TEAM_T)
        g_tUnpaused = true;
      else if (team == CS_TEAM_CT)
        g_ctUnpaused = true;

      if (g_tUnpaused && g_ctUnpaused) {
        Unpause();
        if (IsPlayer(client)) {
          PugSetup_MessageToAll("%t", "Unpause", client);
        }
      } else if (g_tUnpaused && !g_ctUnpaused) {
        PugSetup_MessageToAll("%t", "MutualUnpauseMessage", "T", "CT", unpauseCmd);
      } else if (!g_tUnpaused && g_ctUnpaused) {
        PugSetup_MessageToAll("%t", "MutualUnpauseMessage", "CT", "T", unpauseCmd);
      }
    }
  }

  return Plugin_Handled;
}

public Action Command_Ready(int client, int args) {
  if (!DoPermissionCheck(client, "sm_ready")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  PugSetup_ReadyPlayer(client);
  return Plugin_Handled;
}

public Action Command_NotReady(int client, int args) {
  if (!DoPermissionCheck(client, "sm_notready")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  PugSetup_UnreadyPlayer(client);
  return Plugin_Handled;
}

public Action Command_Leader(int client, int args) {
  if (g_GameState == GameState_None)
    return Plugin_Handled;

  if (!DoPermissionCheck(client, "sm_leader")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char buffer[64];
  if (GetCmdArgs() >= 1) {
    GetCmdArg(1, buffer, sizeof(buffer));
    int target = FindTarget(client, buffer, true, false);
    if (IsPlayer(target))
      PugSetup_SetLeader(target);
  } else if (IsClientInGame(client)) {
    LeaderMenu(client);
  }

  return Plugin_Handled;
}

public Action Command_AddMap(int client, int args) {
  if (!DoPermissionCheck(client, "sm_addmap")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char mapName[PLATFORM_MAX_PATH];
  char durationString[32];
  bool perm = true;

  if (args >= 1 && GetCmdArg(1, mapName, sizeof(mapName))) {
    if (args >= 2 && GetCmdArg(2, durationString, sizeof(durationString))) {
      perm = StrEqual(durationString, "perm", false);
    }

    if (UsingWorkshopCollection()) {
      perm = false;
    }

    if (AddMap(mapName, g_MapList)) {
      PugSetup_Message(client, "Succesfully added map %s", mapName);
      if (perm && !AddToMapList(mapName)) {
        PugSetup_Message(client, "Failed to add map to maplist file.");
      }
    } else {
      PugSetup_Message(client, "Map could not be found: %s", mapName);
    }
  } else {
    PugSetup_Message(client, "Usage: .addmap <map> [temp|perm] (default perm)");
  }

  return Plugin_Handled;
}

public Action Command_RemoveMap(int client, int args) {
  if (!DoPermissionCheck(client, "sm_removemap")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char mapName[PLATFORM_MAX_PATH];
  char durationString[32];
  bool perm = true;

  if (args >= 1 && GetCmdArg(1, mapName, sizeof(mapName))) {
    if (args >= 2 && GetCmdArg(2, durationString, sizeof(durationString))) {
      perm = StrEqual(durationString, "perm", false);
    }

    if (UsingWorkshopCollection()) {
      perm = false;
    }

    if (RemoveMap(mapName, g_MapList)) {
      PugSetup_Message(client, "Succesfully removed map %s", mapName);
      if (perm && !RemoveMapFromList(mapName)) {
        PugSetup_Message(client, "Failed to remove map from maplist file.");
      }
    } else {
      PugSetup_Message(client, "Map %s was not found", mapName);
    }
  } else {
    PugSetup_Message(client, "Usage: .addmap <map> [temp|perm] (default perm)");
  }

  return Plugin_Handled;
}

public Action Command_AddAlias(int client, int args) {
  if (!DoPermissionCheck(client, "sm_addalias")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char alias[ALIAS_LENGTH];
  char command[COMMAND_LENGTH];

  if (args >= 2 && GetCmdArg(1, alias, sizeof(alias)) && GetCmdArg(2, command, sizeof(command))) {
    // try a lookup to find a valid command, e.g., if command=.ready, replace .ready with sm_ready
    if (!PugSetup_IsValidCommand(command)) {
      FindComandFromAlias(command, command);
    }

    if (!PugSetup_IsValidCommand(command)) {
      PugSetup_Message(client, "%s is not a valid pugsetup command.", command);
      PugSetup_Message(client, "Usage: .addalias <alias> <command>");
    } else {
      PugSetup_AddChatAlias(alias, command);
      if (PugSetup_AddChatAliasToFile(alias, command))
        PugSetup_Message(client, "Succesfully added %s as an alias of commmand %s", alias, command);
      else
        PugSetup_Message(client, "Failed to add chat alias");
    }
  } else {
    PugSetup_Message(client, "Usage: .addalias <alias> <command>");
  }

  return Plugin_Handled;
}

public Action Command_RemoveAlias(int client, int args) {
  if (!DoPermissionCheck(client, "sm_addalias")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char alias[ALIAS_LENGTH];
  if (args >= 1 && GetCmdArg(1, alias, sizeof(alias))) {
    int index = -1;  // index of the alias inside g_ChatAliases
    char tmpAlias[ALIAS_LENGTH];
    for (int i = 0; i < g_ChatAliases.Length; i++) {
      g_ChatAliases.GetString(i, tmpAlias, sizeof(tmpAlias));
      if (StrEqual(alias, tmpAlias, false)) {
        index = i;
        break;
      }
    }

    if (index == -1) {
      PugSetup_Message(client, "%s is not currently a chat alias", alias);
    } else {
      g_ChatAliasesCommands.Erase(index);
      g_ChatAliases.Erase(index);
      g_ChatAliasesModes.Erase(index);

      if (RemoveChatAliasFromFile(alias))
        PugSetup_Message(client, "Succesfully removed alias %s", alias);
      else
        PugSetup_Message(client, "Failed to remove chat alias");
    }
  } else {
    PugSetup_Message(client, "Usage: .removealias <alias>");
  }

  return Plugin_Handled;
}

public Action Command_SetDefault(int client, int args) {
  if (!DoPermissionCheck(client, "sm_setdefault")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char setting[32];
  char value[32];

  if (args >= 2 && GetCmdArg(1, setting, sizeof(setting)) && GetCmdArg(2, value, sizeof(value))) {
    if (CheckSetupOptionValidity(client, setting, value, true, false)) {
      if (SetDefaultInFile(setting, value))
        PugSetup_Message(client, "Succesfully set default option %s as %s", setting, value);
      else
        PugSetup_Message(client, "Failed to write default setting to file");
    }
  } else {
    PugSetup_Message(client, "Usage: .setdefault <setting> <default>");
  }

  return Plugin_Handled;
}

public Action Command_SetDisplay(int client, int args) {
  if (!DoPermissionCheck(client, "sm_setdisplay")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  char setting[32];
  char value[32];

  if (args >= 2 && GetCmdArg(1, setting, sizeof(setting)) && GetCmdArg(2, value, sizeof(value))) {
    if (CheckSetupOptionValidity(client, setting, value, false, true)) {
      if (SetDisplayInFile(setting, CheckEnabledFromString(value)))
        PugSetup_Message(client, "Succesfully set display for setting %s as %s", setting, value);
      else
        PugSetup_Message(client, "Failed to write display setting to file");
    }
  } else {
    PugSetup_Message(client, "Usage: .setdefault <setting> <0/1>");
  }

  return Plugin_Handled;
}

public Action Command_ReadyMessage(int client, int args) {
  if (!DoPermissionCheck(client, "sm_readymessage")) {
    if (IsValidClient(client))
      PugSetup_Message(client, "%t", "NoPermission");
    return Plugin_Handled;
  }

  if (g_AllowCustomReadyMessageCvar.IntValue != 0) {
    char message[256];
    GetCmdArgString(message, sizeof(message));
    SetClientCookie(client, g_ReadyMessageCookie, message);
    PugSetup_Message(client, "%t", "SavedReadyMessage");
  }

  return Plugin_Handled;
}

/***********************
 *                     *
 *       Events        *
 *                     *
 ***********************/

public Action Event_MatchOver(Event event, const char[] name, bool dontBroadcast) {
  if (g_GameState == GameState_Live) {
    CreateTimer(15.0, Timer_EndMatch);
    ExecCfg(g_WarmupCfgCvar);

    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));
    g_PastMaps.PushString(map);
  }

  if (g_PastMaps.Length > g_ExcludedMaps.IntValue) {
    g_PastMaps.Erase(0);
  }

  return Plugin_Continue;
}

/** Helper timer to delay starting warmup period after match is over by a little bit **/
public Action Timer_EndMatch(Handle timer) {
  EndMatch(false, false);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
  CheckAutoSetup();
  CheckSidesRoundForGrenades();
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
  if (g_GameState == GameState_SidesRound) {
    ChangeState(GameState_WaitingForSidesRoundDecision);
    g_SidesWinner = GetSidesRoundWinner();
    LogDebug("Set g_SidesWinner = %d", g_SidesWinner);

    char teamString[4];
    if (g_SidesWinner == CS_TEAM_CT)
      teamString = "CT";
    else
      teamString = "T";

    char stayCmd[ALIAS_LENGTH];
    char swapCmd[ALIAS_LENGTH];
    FindAliasFromCommand("sm_stay", stayCmd);
    FindAliasFromCommand("sm_swap", swapCmd);

    if (g_DoVoteForSidesRoundDecisionCvar.IntValue != 0) {
      CreateTimer(20.0, Timer_HandleSidesDecisionVote, _, TIMER_FLAG_NO_MAPCHANGE);
      PugSetup_MessageToAll("%t", "KnifeRoundWinnerVote", teamString, stayCmd, swapCmd);
    } else {
      PugSetup_MessageToAll("%t", "KnifeRoundWinner", teamString, stayCmd, swapCmd);
    }

    Pause();

  }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
  if (g_GameState != GameState_Warmup)
    return;

  int client = GetClientOfUserId(event.GetInt("userid"));
  if (IsPlayer(client) && OnActiveTeam(client) && g_WarmupMoneyOnSpawnCvar.IntValue != 0) {
    SetEntProp(client, Prop_Send, "m_iAccount", GetCvarIntSafe("mp_maxmoney"));
  }
}

public Action Event_PlayerConnect(Event event, const char[] name, bool dontBroadcast) {
  int userid = event.GetInt("userid");
  int client = GetClientOfUserId(userid);
  g_Teams[client] = CS_TEAM_NONE;
  g_PlayerAtStart[client] = false;
}

public Action Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
  int userid = event.GetInt("userid");
  int client = GetClientOfUserId(userid);
  if (g_Leader == client)
    g_Leader = -1;
  if (g_capt1 == client)
    g_capt1 = -1;
  if (g_capt2 == client)
    g_capt2 = -1;
}

/**
 * Silences cvar changes when executing live/knife/warmup configs, *unless* it's sv_cheats.
 */
public Action Event_CvarChanged(Event event, const char[] name, bool dontBroadcast) {
  if (g_GameState != GameState_None) {
    char cvarName[128];
    event.GetString("cvarname", cvarName, sizeof(cvarName));
    if (!StrEqual(cvarName, "sv_cheats")) {
      event.BroadcastDisabled = true;
    }
  }

  return Plugin_Continue;
}

/***********************
 *                     *
 *   Pugsetup logic    *
 *                     *
 ***********************/

public void PrintSetupInfo(int client) {
  if (IsPlayer(g_Leader))
    PugSetup_Message(client, "%t", "SetupBy", g_Leader);

  // print each setup option avaliable
  char buffer[128];

  if (g_DisplayMapType) {
    GetMapString(buffer, sizeof(buffer), g_MapType, client);
    PugSetup_Message(client, "%t: {GREEN}%s", "MapTypeOption", buffer);
  }

  PugSetup_Message(client, "%t: {GREEN}%s", "GameTypeOption", GetGameMode() == const_GameModeWingman ? "Wingman" : "Competitive");

  PugSetup_Message(client, "%t: {GREEN}%s", "FriendlyFireOption", g_FriendlyFire ? "Yes" : "No");

  if (g_DisplayTeamSize || g_DisplayTeamType) {
    GetTeamString(buffer, sizeof(buffer), g_TeamType, client);
    PugSetup_Message(client, "%t: ({GREEN}%d vs %d{NORMAL}) {GREEN}%s", "TeamTypeOption",
                     g_PlayersPerTeam, g_PlayersPerTeam, buffer);
  }

  if (g_DisplayRecordDemo) {
    GetEnabledString(buffer, sizeof(buffer), g_RecordGameOption, client);
    PugSetup_Message(client, "%t: {GREEN}%s", "DemoOption", buffer);
  }

  if (g_DisplaySidesRound) {
    GetSidesString(buffer, sizeof(buffer), g_SidesRound, client);
    PugSetup_Message(client, "%t: {GREEN}%s", "SidesRoundOption", buffer);
  }

  if (g_DisplayAutoLive) {
    GetEnabledString(buffer, sizeof(buffer), g_AutoLive, client);
    PugSetup_Message(client, "%t: {GREEN}%s", "AutoLiveOption", buffer);
  }

  if (g_DisplayPlayout) {
    GetEnabledString(buffer, sizeof(buffer), g_DoPlayout, client);
    PugSetup_Message(client, "%t: {GREEN}%s", "PlayoutOption", buffer);
  }
}

public void ReadyToStart() {
  Call_StartForward(g_hOnReadyToStart);
  Call_Finish();

  char teamName1[PLATFORM_MAX_PATH];
  char teamName2[PLATFORM_MAX_PATH];

  GetConVarString(g_TeamName1Cvar, teamName1, PLATFORM_MAX_PATH);
  GetConVarString(g_TeamName2Cvar, teamName2, PLATFORM_MAX_PATH);

  if (strlen(teamName1) > 0 && strlen(teamName2) > 0) {

      SetTeamInfo(CS_TEAM_CT, teamName1, "");
      SetTeamInfo(CS_TEAM_T, teamName2, "");
      ShowWaitingForStartHint();
      CreateTimer(1.0, Timer_ShowWaitingForStartHint, _, TIMER_REPEAT);
      
  }

  if (g_AutoLive) {
    StartGame();
  } else {
    ChangeState(GameState_WaitingForStart);
    CreateTimer(float(START_COMMAND_HINT_TIME), Timer_StartCommandHint);
    GiveStartCommandHint();
  }
}

public void ShowWaitingForStartHint() {

  char teamName1[PLATFORM_MAX_PATH];
  char teamName2[PLATFORM_MAX_PATH];

  GetConVarString(g_TeamName1Cvar, teamName1, PLATFORM_MAX_PATH);
  GetConVarString(g_TeamName2Cvar, teamName2, PLATFORM_MAX_PATH);

  char leader[64];

  GetClientName(PugSetup_GetLeader(), leader, sizeof(leader));

  for (int i = 1; i <= MaxClients; i++) {

    if (IsPlayer(i)) {

      int playerTeam = GetClientTeam(i);
      if (playerTeam == CS_TEAM_CT) {
          PrintHintText(i, "%t", "WaitingForStartHint", teamName1, leader);
      } else if (playerTeam == CS_TEAM_T) {
          PrintHintText(i, "%t", "WaitingForStartHint", teamName2, leader);
      }

    }

  }

}

public Action Timer_ShowWaitingForStartHint(Handle timer) {
  if (g_GameState != GameState_WaitingForStart) {
    return Plugin_Stop;
  }

  ShowWaitingForStartHint();

  return Plugin_Continue;

}

static void GiveStartCommandHint() {
  char startCmd[ALIAS_LENGTH];
  FindAliasFromCommand("sm_start", startCmd);
  PugSetup_MessageToAll("%t", "WaitingForStart", PugSetup_GetLeader(), startCmd);
}

public Action Timer_StartCommandHint(Handle timer) {
  if (g_GameState != GameState_WaitingForStart) {
    return Plugin_Handled;
  }
  GiveStartCommandHint();
  return Plugin_Continue;
}

public Action Timer_CountDown(Handle timer) {
  if (g_GameState != GameState_Countdown) {
    // match cancelled
    PugSetup_MessageToAll("%t", "CancelCountdownMessage");
    return Plugin_Stop;
  }

  if (g_AnnounceCountdownCvar.IntValue != 0) {

      PrintHintTextToAll("%t", "CountDownToLive", g_CountDownTicks);
      PugSetup_MessageToAll("%t", "Countdown", g_CountDownTicks);
    }

  if (g_CountDownTicks <= 1) {
    
    // reset startmoney and grenade count
    ServerCommand("mp_startmoney 800;ammo_grenade_limit_default 1;sv_maxspeed 320");
    BeginLO3();
    return Plugin_Stop;

  }

  g_CountDownTicks--;

  return Plugin_Continue;
}

public void StartGame() {

  for (int i = 1; i <= MaxClients; i++) {
    g_PlayerAtStart[i] = IsPlayer(i);
  }

  if (g_TeamType == TeamType_Autobalanced) {
    if (!PugSetup_IsTeamBalancerAvaliable()) {
      LogError(
          "Match setup with autobalanced teams without a balancer avaliable - falling back to random teams");
      g_TeamType = TeamType_Random;
    } else {
      ArrayList players = new ArrayList();
      for (int i = 1; i <= MaxClients; i++) {
        if (IsPlayer(i)) {
          if (PugSetup_IsReady(i))
            players.Push(i);
          else
            ChangeClientTeam(i, CS_TEAM_SPECTATOR);
        }
      }

      char buffer[128];
      GetPluginFilename(g_BalancerFunctionPlugin, buffer, sizeof(buffer));
      LogDebug("Running autobalancer function from plugin %s", buffer);

      Call_StartFunction(g_BalancerFunctionPlugin, g_BalancerFunction);
      Call_PushCell(players);
      Call_Finish();
      delete players;
    }
  }

  if (g_TeamType == TeamType_Random) {
    PugSetup_MessageToAll("%t", "Scrambling");
    ScrambleTeams();
  }

  // dont know why we need this delay
  if (InWarmup()) {
    EndWarmup();
  }

  if (g_SidesRound == SidesRound_None) {

    StartCountDown();

  } else {

    ChangeState(GameState_SidesRound);
    StartSidesRound(g_SidesRound);

  }
  
}

public void StartCountDown() {

  ExecGameConfigs();

  // Remove money during countdown to not confuse people and have them buy twice.
  ServerCommand("mp_startmoney 0");
  ServerCommand(g_FriendlyFire ? "mp_friendlyfire 1" : "mp_friendlyfire 0");
  g_CountDownTicks = 6;
  Pause();
  RestartGame(1);
  ChangeState(GameState_Countdown);
  CreateTimer(1.0, Timer_CountDown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

}

public void ScrambleTeams() {
  int tCount = 0;
  int ctCount = 0;

  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i) &&
        (g_ExcludeSpectatorsCvar.IntValue == 0 || GetClientTeam(i) != CS_TEAM_SPECTATOR)) {
      if (tCount < g_PlayersPerTeam && ctCount < g_PlayersPerTeam) {
        bool ct = (GetRandomInt(0, 1) == 0);
        if (ct) {
          SwitchPlayerTeam(i, CS_TEAM_CT);
          ctCount++;
        } else {
          SwitchPlayerTeam(i, CS_TEAM_T);
          tCount++;
        }

      } else if (tCount < g_PlayersPerTeam && ctCount >= g_PlayersPerTeam) {
        // CT is full
        SwitchPlayerTeam(i, CS_TEAM_T);
        tCount++;

      } else if (ctCount < g_PlayersPerTeam && tCount >= g_PlayersPerTeam) {
        // T is full
        SwitchPlayerTeam(i, CS_TEAM_CT);
        ctCount++;

      } else {
        // both teams full
        SwitchPlayerTeam(i, CS_TEAM_SPECTATOR);
        Call_StartForward(g_hOnNotPicked);
        Call_PushCell(i);
        Call_Finish();
      }
    }
  }
}

public void ExecWarmupConfigs() {
  ExecCfg(g_WarmupCfgCvar);
  if (OnAimMap() && g_DoAimWarmup && !g_OnDecidedMap) {
    ServerCommand("exec sourcemod/pugsetup/aim_warmup.cfg");
  }
}

public void ExecGameConfigs() {
  // Exec default 5v5 or 2v2 game config depending on game mode. 1 = 5v5, 2 = 2v2
  ServerCommand(GetGameMode() == const_GameModeWingman ? "exec gamemode_competitive2v2_server" : "exec gamemode_competitive_server");

  ExecCfg(g_LiveCfgCvar);
  if (InWarmup())
    EndWarmup();

  // if force playout selected, set that cvar now
  if (g_DoPlayout) {
    ServerCommand("mp_match_can_clinch 0");

    // Note: the game will automatically go to overtime with playout enabled,
    // (even if the score is 29-1, for example) which doesn't make sense generally,
    // so we explicitly disable overtime here.
    ServerCommand("mp_overtime_enable 0");
  } else {
    ServerCommand("mp_match_can_clinch 1");
  }
}

stock void EndMatch(bool execConfigs = true, bool doRestart = true) {
  if (g_GameState == GameState_None) {
    return;
  }

  if (g_Recording) {
    CreateTimer(4.0, StopDemo, _, TIMER_FLAG_NO_MAPCHANGE);
  } else {
    Call_StartForward(g_hOnMatchOver);
    Call_PushCell(false);
    Call_PushString("");
    Call_Finish();
  }

  g_LiveTimerRunning = false;
  g_Leader = -1;
  g_capt1 = -1;
  g_capt2 = -1;
  g_OnDecidedMap = false;
  ChangeState(GameState_None);

  if (g_KnifeCvarRestore != INVALID_HANDLE) {
    RestoreCvars(g_KnifeCvarRestore);
    CloseCvarStorage(g_KnifeCvarRestore);
    g_KnifeCvarRestore = INVALID_HANDLE;
  }

  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      UpdateClanTag(i);
    }
  }

  if (execConfigs) {
    ExecCfg(g_PostGameCfgCvar);
  }
  if (IsPaused()) {
    Unpause();
  }
  if (InWarmup()) {
    EndWarmup();
  }
  if (doRestart) {
    RestartGame(1);
  }

  StartSetupHint();

}

public void StartSetupHint() {

  CreateTimer(20.0, Timer_ShowSetupHint, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);  

}

public Action ShowSetupHint(Handle timer) {

  if (g_GameState != GameState_None) {
    return Plugin_Stop;
  }

  PrintHintTextToAll("%t", "SetupHint");
  return Plugin_Handled;

}

public Action Timer_ShowSetupHint(Handle timer) {

  if (g_GameState != GameState_None) {
    return Plugin_Stop;
  }

  ShowSetupHint(null);
  CreateTimer(3.0, ShowSetupHint); // Show again after 4 seconds. Text is long.

  return Plugin_Continue;

}

public void SetupMapVotePool(bool excludeRecentMaps) {
  g_MapVotePool.Clear();

  char mapNamePrimary[PLATFORM_MAX_PATH];
  char mapNameSecondary[PLATFORM_MAX_PATH];

  for (int i = 0; i < g_MapList.Length; i++) {
    bool mapExists = false;
    FormatMapName(g_MapList, i, mapNamePrimary, sizeof(mapNamePrimary));
    for (int v = 0; v < g_PastMaps.Length; v++) {
      g_PastMaps.GetString(v, mapNameSecondary, sizeof(mapNameSecondary));
      if (StrEqual(mapNamePrimary, mapNameSecondary)) {
        mapExists = true;
      }
    }
    if (!mapExists || !excludeRecentMaps) {
      g_MapVotePool.PushString(mapNamePrimary);
    }
  }
}

public Action MapSetup(Handle timer) {
  if (g_MapType == MapType_Vote) {
    CreateMapVote();
  } else if (g_MapType == MapType_Veto) {
    CreateMapVeto();
  } else {
    LogError("Unexpected map type in MapSetup=%d", g_MapType);
  }
  return Plugin_Handled;
}

public Action StartPicking(Handle timer) {
  ChangeState(GameState_PickingPlayers);
  Pause();
  RestartGame(1);

  CreateTimer(1.0, Timer_ShowPickMessage, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      g_Teams[i] = CS_TEAM_SPECTATOR;
      SwitchPlayerTeam(i, CS_TEAM_SPECTATOR);
    } else {
      g_Teams[i] = CS_TEAM_NONE;
    }
  }

  // temporary teams
  SwitchPlayerTeam(g_capt2, CS_TEAM_CT);
  g_Teams[g_capt2] = CS_TEAM_CT;

  SwitchPlayerTeam(g_capt1, CS_TEAM_T);
  g_Teams[g_capt1] = CS_TEAM_T;

  CreateTimer(2.0, Timer_InitialChoiceMenu);
  return Plugin_Handled;
}

public Action ShowPickMessage()
{

    char captain1Name[64];
    char captain2Name[64];
    
    GetClientName(PugSetup_GetCaptain(1),captain1Name,sizeof(captain1Name));
    GetClientName(PugSetup_GetCaptain(2),captain2Name,sizeof(captain2Name));

    char playerList[512];
    char playerName[64];
    
    int first = 1;

    for (int i = 1; i <= MaxClients; i++) {
      if (IsPlayer(i) && !IsPlayerPicked(i)) {

        if (!first) {
          StrCat(playerList, sizeof(playerList), "\n"); 
        } else {
          first = 0;
        }

        GetClientName(i, playerName, sizeof(playerName));
        StrCat(playerList, sizeof(playerList), playerName);
      }
    }
  
    PrintHintTextToAll("Please wait while %s and %s pick teams.\n\nRemaining players:\n%s", captain1Name, captain2Name, playerList);

}

public Action Timer_ShowPickMessage(Handle timer) {
  if (g_GameState != GameState_PickingPlayers) {
    return Plugin_Stop;
  }

  ShowPickMessage();

  return Plugin_Continue;

}

public Action FinishPicking(Handle timer) {
  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      if (g_Teams[i] == CS_TEAM_NONE || g_Teams[i] == CS_TEAM_SPECTATOR) {
        SwitchPlayerTeam(i, CS_TEAM_SPECTATOR);
        Call_StartForward(g_hOnNotPicked);
        Call_PushCell(i);
        Call_Finish();
      } else {
        SwitchPlayerTeam(i, g_Teams[i]);
      }
    }
  }

  ReadyToStart();

  return Plugin_Handled;
}

stock bool IsPlayerPicked(int client) {
  int team = g_Teams[client];
  return team == CS_TEAM_T || team == CS_TEAM_CT;
}

public Action StopDemo(Handle timer) {
  StopRecording();
  g_Recording = false;
  Call_StartForward(g_hOnMatchOver);
  Call_PushCell(true);
  Call_PushString(g_DemoFileName);
  Call_Finish();
  return Plugin_Handled;
}

public void CheckAutoSetup() {
  if (g_AutoSetupCvar.IntValue != 0 && g_GameState == GameState_None && !g_ForceEnded) {
    // Re-fetch the defaults
    ReadSetupOptions();
    SetupFinished();
  }
}

public void CheckSidesRoundForGrenades() {
  if (g_GameState != GameState_SidesRound) {
    return;
  }

  if (g_SidesRound != SidesRound_Grenades) {
    return;
  }

  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i) && !IsClientObserver(i)) {
      GivePlayerItem(i, "weapon_hegrenade");
      GivePlayerItem(i, "weapon_hegrenade");
      GivePlayerItem(i, "weapon_hegrenade");
      GivePlayerItem(i, "weapon_hegrenade");
    }
  }

}

public void ExecCfg(ConVar cvar) {
  char cfg[PLATFORM_MAX_PATH];
  cvar.GetString(cfg, sizeof(cfg));

  // for files that start with configs/pugsetup/* we just
  // read the file and execute each command individually,
  // otherwise we assume the file is in the cfg/ directory and
  // just use the game's exec command.
  if (StrContains(cfg, "configs/pugsetup") == 0) {
    char formattedPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, formattedPath, sizeof(formattedPath), cfg);
    ExecFromFile(formattedPath);
  } else {
    ServerCommand("exec \"%s\"", cfg);
  }

  if (cvar == g_LiveCfgCvar) {
    Call_StartForward(g_hOnLiveCfg);
    Call_Finish();
  } else if (cvar == g_WarmupCfgCvar) {
    Call_StartForward(g_hOnWarmupCfg);
    Call_Finish();
  } else if (cvar == g_PostGameCfgCvar) {
    Call_StartForward(g_hOnPostGameCfg);
    Call_Finish();
  }
}

public void ExecFromFile(const char[] path) {
  if (FileExists(path)) {
    File file = OpenFile(path, "r");
    if (file != null) {
      char buffer[256];
      while (!file.EndOfFile() && file.ReadLine(buffer, sizeof(buffer))) {
        ServerCommand(buffer);
      }
      delete file;
    } else {
      LogError("Failed to open config file for reading: %s", path);
    }
  } else {
    LogError("Config file does not exist: %s", path);
  }
}

stock void UpdateClanTag(int client, bool strip = false) {
  if (IsPlayer(client) && GetClientTeam(client) != CS_TEAM_NONE) {
    if (!g_SavedClanTag[client]) {
      CS_GetClientClanTag(client, g_ClanTag[client], CLANTAG_LENGTH);
      g_SavedClanTag[client] = true;
    }

    // don't bother with crazy things when the plugin isn't active
    if (g_GameState == GameState_Live || g_GameState == GameState_None || strip) {
      RestoreClanTag(client);
      return;
    }

    int team = GetClientTeam(client);
    if (g_ExcludeSpectatorsCvar.IntValue == 0 || team == CS_TEAM_CT || team == CS_TEAM_T) {
      char tag[32];
      if (g_Ready[client]) {
        Format(tag, sizeof(tag), "%T", "Ready", LANG_SERVER);
      } else {
        Format(tag, sizeof(tag), "%T", "NotReady", LANG_SERVER);
      }
      CS_SetClientClanTag(client, tag);
    } else {
      RestoreClanTag(client);
    }
  }
}

// Restores the clan tag to a client's original setting, or the empty string if it was never saved.
public void RestoreClanTag(int client) {
  if (g_SavedClanTag[client]) {
    CS_SetClientClanTag(client, g_ClanTag[client]);
  } else {
    CS_SetClientClanTag(client, "");
  }
}

public void ChangeState(GameState state) {
  LogDebug("Change from state %d -> %d", g_GameState, state);
  Call_StartForward(g_hOnStateChange);
  Call_PushCell(g_GameState);
  Call_PushCell(state);
  Call_Finish();
  g_GameState = state;
}

stock bool TeamTypeFromString(const char[] teamTypeString, TeamType& teamType,
                              bool logError = false) {
  if (StrEqual(teamTypeString, "captains", false) || StrEqual(teamTypeString, "captain", false)) {
    teamType = TeamType_Captains;
  } else if (StrEqual(teamTypeString, "manual", false)) {
    teamType = TeamType_Manual;
  } else if (StrEqual(teamTypeString, "random", false)) {
    teamType = TeamType_Random;
  } else if (StrEqual(teamTypeString, "autobalanced", false) ||
             StrEqual(teamTypeString, "balanced", false)) {
    teamType = TeamType_Autobalanced;
  } else {
    if (logError)
      LogError(
          "Invalid team type: \"%s\", allowed values: \"captains\", \"manual\", \"random\", \"autobalanced\"",
          teamTypeString);
    return false;
  }

  return true;
}

stock bool SidesRoundFromString(const char[] sidesRoundString, SidesRound& sidesRound, bool logError = false) {
  if (StrEqual(sidesRoundString, "none", false)) {
    sidesRound = SidesRound_None;
  } else if (StrEqual(sidesRoundString, "knife", false)) {
    sidesRound = SidesRound_Knife;
  } else if (StrEqual(sidesRoundString, "deagle", false)) {
    sidesRound = SidesRound_Deagle;
  } else if (StrEqual(sidesRoundString, "scout", false)) {
    sidesRound = SidesRound_Scout;
  } else if (StrEqual(sidesRoundString, "grenades", false)) {
    sidesRound = SidesRound_Grenades;
  } else {
    if (logError)
      LogError("Invalid sides type: \"%s\", allowed values: \"none\", \"knife\", \"deagle\", \"scout\", \"grenades\".",
               sidesRoundString);
    return false;
  }

  return true;
}

stock bool MapTypeFromString(const char[] mapTypeString, MapType& mapType, bool logError = false) {
  if (StrEqual(mapTypeString, "current", false)) {
    mapType = MapType_Current;
  } else if (StrEqual(mapTypeString, "vote", false)) {
    mapType = MapType_Vote;
  } else if (StrEqual(mapTypeString, "veto", false)) {
    mapType = MapType_Veto;
  } else {
    if (logError)
      LogError("Invalid map type: \"%s\", allowed values: \"current\", \"vote\", \"veto\"",
               mapTypeString);
    return false;
  }

  return true;
}

stock bool PermissionFromString(const char[] permissionString, Permission& p,
                                bool logError = false) {
  if (StrEqual(permissionString, "all", false) || StrEqual(permissionString, "any", false)) {
    p = Permission_All;
  } else if (StrEqual(permissionString, "captains", false) ||
             StrEqual(permissionString, "captain", false)) {
    p = Permission_Captains;
  } else if (StrEqual(permissionString, "leader", false)) {
    p = Permission_Leader;
  } else if (StrEqual(permissionString, "admin", false)) {
    p = Permission_Admin;
  } else if (StrEqual(permissionString, "none", false)) {
    p = Permission_None;
  } else {
    if (logError)
      LogError(
          "Invalid permission type: \"%s\", allowed values: \"all\", \"captain\", \"leader\", \"admin\", \"none\"",
          permissionString);
    return false;
  }

  return true;
}
