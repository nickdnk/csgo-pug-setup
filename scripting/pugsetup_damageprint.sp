#include <cstrike>
#include <sourcemod>

#include "include/pugsetup.inc"
#include "pugsetup/util.sp"

#pragma semicolon 1
#pragma newdecls required

ConVar g_hAllowDmgCommand;
ConVar g_hEnabled;
ConVar g_hMessageFormat;

int g_DamageDone[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_DamageDoneHits[MAXPLAYERS + 1][MAXPLAYERS + 1];
int g_DamageDoneUtility[MAXPLAYERS + 1];
int g_EnemiesFlashed[MAXPLAYERS + 1];
bool g_GotKill[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_GotKnifeKill[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_GotHeadshot[MAXPLAYERS + 1][MAXPLAYERS + 1];
bool g_GotAssist[MAXPLAYERS + 1][MAXPLAYERS + 1];

// clang-format off
public Plugin myinfo = {
    name = "CS:GO PugSetup: damage printer",
    author = "splewis",
    description = "Writes out player damage on round end or when .dmg is used",
    version = PLUGIN_VERSION,
    url = "https://github.com/splewis/csgo-pug-setup"
};
// clang-format on

public void OnPluginStart() {
  LoadTranslations("pugsetup.phrases");
  g_hEnabled =
      CreateConVar("sm_pugsetup_damageprint_enabled", "1", "Whether the plugin is enabled");
  g_hAllowDmgCommand = CreateConVar("sm_pugsetup_damageprint_allow_dmg_command", "1",
                                    "Whether players can type .dmg to see damage done");
  g_hMessageFormat = CreateConVar(
      "sm_pugsetup_damageprint_format",
      "{NAME} ({HEALTH}{HAS_HP_LEFT}) | {DMG_TO} in {HITS_TO} {HIT_OR_HITS_TO}{IS_HS_TO} | {DMG_FROM} in {HITS_FROM} {HIT_OR_HITS_FROM}{IS_HS_FROM}.",
      "Format of the damage output string. Avaliable tags are in the default, color tags such as {LIGHT_RED} and {GREEN} also work.");

  AutoExecConfig(true, "pugsetup_damageprint", "sourcemod/pugsetup");

  RegConsoleCmd("sm_dmg", Command_Damage, "Displays damage done");
  PugSetup_AddChatAlias(".dmg", "sm_dmg");

  HookEvent("round_start", Event_RoundStart);
  HookEvent("player_hurt", Event_DamageDealt, EventHookMode_Pre);
  HookEvent("player_death", Event_PlayerDeath);
  HookEvent("player_blind", Event_PlayerBlind);
  HookEvent("round_end", Event_RoundEnd, EventHookMode_Post);
}

static void GetDamageColor(char color[16], bool damageGiven, int damage, bool gotKill) {
  if (damage == 0) {
    Format(color, sizeof(color), "NORMAL");
  } else if (damageGiven) {
    if (gotKill) {
      Format(color, sizeof(color), "GREEN");
    } else {
      Format(color, sizeof(color), "LIGHT_GREEN");
    }
  } else {
    if (gotKill) {
      Format(color, sizeof(color), "DARK_RED");
    } else {
      Format(color, sizeof(color), "LIGHT_RED");
    }
  }
}

static void PrintDamageInfo(int client) {
  if (!IsValidClient(client))
    return;

  int team = GetClientTeam(client);
  if (team != CS_TEAM_T && team != CS_TEAM_CT)
    return;

  char message[256];

  char intro[128] = " {YELLOW} ------- Damage Report ------- {NORMAL}";
  Colorize(intro, sizeof(intro));
  PrintToChat(client, intro);

  int otherTeam = (team == CS_TEAM_T) ? CS_TEAM_CT : CS_TEAM_T;
  for (int i = 1; i <= MaxClients; i++) {
    if (IsValidClient(i) && GetClientTeam(i) == otherTeam) {
      int health = IsPlayerAlive(i) ? GetClientHealth(i) : 0;
      char name[64];
      GetClientName(i, name, sizeof(name));

      g_hMessageFormat.GetString(message, sizeof(message)); 
      // Strip colors first.
      Colorize(message, sizeof(message), true);
      char color[16];

      GetDamageColor(color, true, g_DamageDone[client][i], g_GotKill[client][i]);
      ReplaceStringWithColoredInt(message, sizeof(message), "{DMG_TO}", g_DamageDone[client][i],
                                  color);
      ReplaceStringWithColoredInt(message, sizeof(message), "{HITS_TO}",
                                  g_DamageDoneHits[client][i], color);

      GetDamageColor(color, false, g_DamageDone[i][client], g_GotKill[i][client]);
      ReplaceStringWithColoredInt(message, sizeof(message), "{DMG_FROM}", g_DamageDone[i][client],
                                  color);
      ReplaceStringWithColoredInt(message, sizeof(message), "{HITS_FROM}",
                                  g_DamageDoneHits[i][client], color);

      ReplaceString(message, sizeof(message), "{IS_HS_TO}", g_GotHeadshot[client][i] ? "{GREEN} [HS]{NORMAL}" : g_GotKnifeKill[client][i] ? "{GREEN} [K]{NORMAL}" : g_GotKill[client][i] ? "{GREEN} [X]{NORMAL}" : g_GotAssist[client][i] ? "{GREEN} [A]{NORMAL}" : "");
      ReplaceString(message, sizeof(message), "{IS_HS_FROM}", g_GotHeadshot[i][client] ? "{DARK_RED} [HS]{NORMAL}" : g_GotKnifeKill[i][client] ? "{DARK_RED} [K]{NORMAL}" : g_GotKill[i][client] ? "{DARK_RED} [X]{NORMAL}" : g_GotAssist[i][client] ? "{DARK_RED} [A]{NORMAL}" : "");

      ReplaceString(message, sizeof(message), "{HIT_OR_HITS_TO}", g_DamageDoneHits[client][i] != 1 ? "hits" : "hit");
      ReplaceString(message, sizeof(message), "{HIT_OR_HITS_FROM}", g_DamageDoneHits[i][client] != 1 ? "hits" : "hit");

      ReplaceString(message, sizeof(message), "{NAME}", name);

      if (health > 0) {
        ReplaceString(message, sizeof(message), "{HAS_HP_LEFT}", " HP");
        ReplaceStringWithInt(message, sizeof(message), "{HEALTH}", health);
      } else {
        ReplaceString(message, sizeof(message), "{HAS_HP_LEFT}", "dead");
        ReplaceString(message, sizeof(message), "{HEALTH}", "");
      }
      
      Colorize(message, sizeof(message));
      PrintToChat(client, message);

    }
  }

  char utilityFlashMessage[256]  = "You did a total of {GREEN}{UTILITY_DAMAGE}{NORMAL} utility damage and flashed {GREEN}{ENEMIES_FLASHED}{NORMAL} {ENEMY_OR_ENEMIES}.";

  ReplaceString(utilityFlashMessage, sizeof(utilityFlashMessage), "{ENEMY_OR_ENEMIES}", g_EnemiesFlashed[client] == 1 ? "enemy" : "enemies");
  ReplaceStringWithInt(utilityFlashMessage, sizeof(utilityFlashMessage), "{ENEMIES_FLASHED}", g_EnemiesFlashed[client]);
  ReplaceStringWithInt(utilityFlashMessage, sizeof(utilityFlashMessage), "{UTILITY_DAMAGE}", g_DamageDoneUtility[client]);
  Colorize(utilityFlashMessage, sizeof(utilityFlashMessage));

  PrintToChat(client, utilityFlashMessage);

  char outro[128] = " {YELLOW} ----------------------------------{NORMAL}";
  Colorize(outro, sizeof(outro));
  PrintToChat(client, outro);

  if (g_DamageDoneUtility[client] > 0 || g_EnemiesFlashed[client] > 0) {
    PrintHintText(client, utilityFlashMessage);
  }

}

public Action Command_Damage(int client, int args) {
  if (!PugSetup_IsMatchLive() || g_hEnabled.IntValue == 0 || g_hAllowDmgCommand.IntValue == 0)
    return Plugin_Handled;

  if (IsPlayerAlive(client)) {
    PugSetup_Message(client, "You cannot use that command when alive.");
    return Plugin_Handled;
  }

  PrintDamageInfo(client);
  return Plugin_Handled;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
  if (!PugSetup_IsMatchLive() || g_hEnabled.IntValue == 0)
    return;

  for (int i = 1; i <= MaxClients; i++) {
    if (IsValidClient(i)) {
      PrintDamageInfo(i);
    }
  }
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
  for (int i = 1; i <= MaxClients; i++) {

    g_DamageDoneUtility[i] = 0;
    g_EnemiesFlashed[i] = 0;

    for (int j = 1; j <= MaxClients; j++) {
      g_DamageDone[i][j] = 0;
      g_DamageDoneHits[i][j] = 0;
      g_GotKill[i][j] = false;
      g_GotKnifeKill[i][j] = false;
      g_GotHeadshot[i][j] = false;
      g_GotAssist[i][j] = false;
    }
  }
}

public Action Event_DamageDealt(Event event, const char[] name, bool dontBroadcast) {
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  int victim = GetClientOfUserId(event.GetInt("userid"));
  bool validAttacker = IsPlayer(attacker) && !IsClientSourceTV(attacker);
  bool validVictim = IsPlayer(victim) && !IsClientSourceTV(victim);

  if (validAttacker && validVictim) {

    // Dont count damage for own team
    int teamAttacker = GetClientTeam(attacker);
    int teamVictim = GetClientTeam(victim);

    if (teamAttacker != teamVictim) {

      int preDamageHealth = GetClientHealth(victim);
      int damage = event.GetInt("dmg_health");
      int postDamageHealth = event.GetInt("health");

      // this maxes the damage variables at 100,
      // so doing 50 damage when the player had 2 health
      // only counts as 2 damage.
      if (postDamageHealth == 0) {
        damage += preDamageHealth;
      }

      g_DamageDone[attacker][victim] += damage;
      g_DamageDoneHits[attacker][victim]++;

      char weapon[32];
      event.GetString("weapon", weapon, 32);

      if (StrEqual(weapon, "hegrenade")
      || StrEqual(weapon, "inferno")
      || StrEqual(weapon, "flashbang")
      || StrEqual(weapon, "smokegrenade")
      || StrEqual(weapon, "decoy"))
        {
        g_DamageDoneUtility[attacker] += damage;
      }
      
    }

  }

}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  int victim = GetClientOfUserId(event.GetInt("userid"));
  int assister = GetClientOfUserId(event.GetInt("assister"));
  bool validAttacker = IsValidClient(attacker) && !IsClientSourceTV(attacker);
  bool validVictim = IsValidClient(victim) && !IsClientSourceTV(victim);
  bool validAssister = IsValidClient(assister) && !IsClientSourceTV(assister);

  if (validAttacker && validVictim) {
    g_GotKill[attacker][victim] = true;

    if (event.GetBool("headshot") == true) {
      g_GotHeadshot[attacker][victim] = true;
    }

    char weapon[32];
    event.GetString("weapon", weapon, 32);

    if (StrEqual(weapon, "knife")) {
      g_GotKnifeKill[attacker][victim] = true;
    }

    if (validAssister && assister > 0) {
      g_GotAssist[assister][victim] = true;
    }

  }
}

public Action Event_PlayerBlind(Event event, const char[] name, bool dontBroadcast) {
  int attacker = GetClientOfUserId(event.GetInt("attacker"));
  int victim = GetClientOfUserId(event.GetInt("userid"));
  bool validAttacker = IsValidClient(attacker) && !IsClientSourceTV(attacker);
  bool validVictim = IsValidClient(victim) && !IsClientSourceTV(victim);

  if (validAttacker && validVictim) {

    float duration = event.GetFloat("blind_duration");
    int teamAttacker = GetClientTeam(attacker);
    int teamVictim = GetClientTeam(victim);

    // Duration 1.2 seems appropriate and the closest match to the in-game scoreboard of registering a flash.
    // There is no event for this counter that can also be tied to attacker - tr_player_flashbanged only has victim.
    if (teamAttacker != teamVictim && duration > 1.2) {

        g_EnemiesFlashed[attacker]++;

       // Flash debugging
       // char flasherName[64];
       // GetClientName(attacker, flasherName, sizeof(flasherName));

       // char victimName[64];
       // GetClientName(victim, victimName, sizeof(victimName));

       // char flashString[64] = "{FLASHER} flashed {VICTIM}: {DUR}";

       // ReplaceString(flashString, sizeof(flashString), "{FLASHER}", flasherName);
       // ReplaceString(flashString, sizeof(flashString), "{VICTIM}", victimName);
       // ReplaceStringWithFloat(flashString, sizeof(flashString), "{DUR}", duration);

       // PrintToChat(attacker, flashString);¨
 
    }
    
  }

}
