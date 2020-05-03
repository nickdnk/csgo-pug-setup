#define KNIFE_CONFIG "sourcemod/pugsetup/knife.cfg"
Handle g_KnifeCvarRestore = INVALID_HANDLE;

public Action StartSidesRound(SidesRound sidesRound) {
  if (g_GameState != GameState_SidesRound)
    return Plugin_Handled;

  // reset player tags
  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      UpdateClanTag(i, true);  // force strip them
    }
  }

  Unpause();

  g_KnifeCvarRestore = ExecuteAndSaveCvars(KNIFE_CONFIG);
  if (g_KnifeCvarRestore == INVALID_HANDLE) {
    LogError("Failed to save cvar values when executing %s", KNIFE_CONFIG);
  }

  if (sidesRound == SidesRound_Deagle) {
    ServerCommand("mp_t_default_secondary weapon_deagle;mp_ct_default_secondary weapon_deagle");
  } else if (sidesRound == SidesRound_Scout) {
    ServerCommand("mp_ct_default_primary weapon_ssg08;mp_t_default_primary weapon_ssg08");
  } else if (sidesRound == SidesRound_Grenades) {
    ServerCommand("ammo_grenade_limit_default 4;sv_maxspeed 190");
  }

  RestartGame(1);

  // Reset sides votes
  g_SidesNumVotesNeeded = g_PlayersPerTeam / 2 + 1;
  for (int i = 1; i <= MaxClients; i++) {
    g_SidesRoundVotes[i] = SidesDecision_None;
  }

  g_SidesMessageCount = 9;

  CreateTimer(1.0, Timer_SidesKnifeText, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
  CreateTimer(1.0, Timer_AnnounceKnife);
 
  return Plugin_Handled;
}

public Action Timer_AnnounceKnife(Handle timer) {
  if (g_GameState != GameState_SidesRound) {
    return Plugin_Handled;
  }

  for (int i = 0; i < 3; i++) {
    PugSetup_MessageToAll("%t", "SidesRound");
  }
    
  return Plugin_Handled;

}

public Action Timer_SidesKnifeText(Handle timer) {
  if (g_GameState != GameState_SidesRound) {
    return Plugin_Stop;
  }

  if (g_SidesMessageCount == 0) {
    return Plugin_Stop;
  }

  if (g_SidesRound == SidesRound_Deagle) {
      PrintHintTextToAll("%t", "StartSidesRoundDeagle");
  } else if (g_SidesRound == SidesRound_Knife) {
      PrintHintTextToAll("%t", "StartSidesRoundKnife");
  } else if (g_SidesRound == SidesRound_Scout) {
      PrintHintTextToAll("%t", "StartSidesRoundScout");
  } else if (g_SidesRound == SidesRound_Grenades) {
      PrintHintTextToAll("%t", "StartSidesRoundGrenades");
  } else {
    return Plugin_Stop;
  }

  g_SidesMessageCount--;
  
  return Plugin_Continue;
}

public Action Timer_HandleSidesDecisionVote(Handle timer) {
  HandleSidesDecisionVote(true);
}

static void HandleSidesDecisionVote(bool timeExpired = false) {
  if (g_GameState != GameState_WaitingForSidesRoundDecision) {
    return;
  }

  int stayCount = 0;
  int swapCount = 0;
  CountSideVotes(stayCount, swapCount);
  if (stayCount >= g_SidesNumVotesNeeded) {
    EndSidesRound(false);
  } else if (swapCount >= g_SidesNumVotesNeeded) {
    EndSidesRound(true);
  } else if (timeExpired) {
    EndSidesRound(swapCount > stayCount);
  }
}

public void CountSideVotes(int& stayCount, int& swapCount) {
  for (int i = 1; i <= MaxClients; i++) {
    if (IsValidClient(i) && GetClientTeam(i) == g_SidesWinner) {
      if (g_SidesRoundVotes[i] == SidesDecision_Stay) {
        stayCount++;
      } else if (g_SidesRoundVotes[i] == SidesDecision_Swap) {
        swapCount++;
      }
    }
  }
  LogDebug("CountSideVotes stayCount=%d, swapCount=%d", stayCount, swapCount);
}

public void EndSidesRound(bool swap) {
  LogDebug("EndSidesRound swap=%d", swap);
  Call_StartForward(g_hOnKnifeRoundDecision);
  Call_PushCell(swap);
  Call_Finish();

  if (swap) {

    char teamName1[PLATFORM_MAX_PATH];
    char teamName2[PLATFORM_MAX_PATH];

    GetConVarString(g_TeamName1Cvar, teamName1, PLATFORM_MAX_PATH);
    GetConVarString(g_TeamName2Cvar, teamName2, PLATFORM_MAX_PATH);

    if (strlen(teamName1) > 0 && strlen(teamName2) > 0) {
      SetTeamInfo(CS_TEAM_T, teamName1, "");
      SetTeamInfo(CS_TEAM_CT, teamName2, "");
    }

    for (int i = 1; i <= MaxClients; i++) {
      if (IsValidClient(i)) {
        int team = GetClientTeam(i);
        if (team == CS_TEAM_T) {
          SwitchPlayerTeam(i, CS_TEAM_CT);
        } else if (team == CS_TEAM_CT) {
          SwitchPlayerTeam(i, CS_TEAM_T);
        } else if (IsClientCoaching(i)) {
          team = GetCoachTeam(i);
          if (team == CS_TEAM_T) {
            UpdateCoachTarget(i, CS_TEAM_CT);
          } else if (team == CS_TEAM_CT) {
            UpdateCoachTarget(i, CS_TEAM_T);
          }
        }
      }
    }
  }

  if (g_KnifeCvarRestore != INVALID_HANDLE) {
    RestoreCvars(g_KnifeCvarRestore);
    CloseCvarStorage(g_KnifeCvarRestore);
    g_KnifeCvarRestore = INVALID_HANDLE;
  }

  StartCountDown();

}

static bool AwaitingDecision(int client, const char[] command) {
  if (g_DoVoteForSidesRoundDecisionCvar.IntValue != 0) {
    return (g_GameState == GameState_WaitingForSidesRoundDecision) && IsPlayer(client) &&
           GetClientTeam(client) == g_SidesWinner;
  } else {
    // Always lets console make the decision
    if (client == 0)
      return true;

    // Check if they're on the winning team
    bool canMakeDecision = (g_GameState == GameState_WaitingForSidesRoundDecision) &&
                           IsPlayer(client) && GetClientTeam(client) == g_SidesWinner;
    bool hasPermissions = DoPermissionCheck(client, command);
    LogDebug("Knife AwaitingDecision Vote: client=%L canMakeDecision=%d, hasPermissions=%d", client,
             canMakeDecision, hasPermissions);
    return canMakeDecision && hasPermissions;
  }
}

public Action Command_Stay(int client, int args) {
  if (AwaitingDecision(client, "sm_stay")) {
    if (g_DoVoteForSidesRoundDecisionCvar.IntValue == 0) {
      EndSidesRound(false);
    } else {
      g_SidesRoundVotes[client] = SidesDecision_Stay;
      PugSetup_Message(client, "%t", "KnifeRoundVoteStay");
      HandleSidesDecisionVote();
    }
  }
  return Plugin_Handled;
}

public Action Command_Swap(int client, int args) {
  if (AwaitingDecision(client, "sm_swap")) {
    if (g_DoVoteForSidesRoundDecisionCvar.IntValue == 0) {
      EndSidesRound(true);
    } else {
      g_SidesRoundVotes[client] = SidesDecision_Swap;
      PugSetup_Message(client, "%t", "KnifeRoundVoteSwap");
      HandleSidesDecisionVote();
    }
  }
  return Plugin_Handled;
}

public Action Command_Ct(int client, int args) {
  if (IsPlayer(client)) {
    if (GetClientTeam(client) == CS_TEAM_CT)
      FakeClientCommand(client, "sm_stay");
    else if (GetClientTeam(client) == CS_TEAM_T)
      FakeClientCommand(client, "sm_swap");
  }
  return Plugin_Handled;
}

public Action Command_T(int client, int args) {
  if (IsPlayer(client)) {
    if (GetClientTeam(client) == CS_TEAM_T)
      FakeClientCommand(client, "sm_stay");
    else if (GetClientTeam(client) == CS_TEAM_CT)
      FakeClientCommand(client, "sm_swap");
  }
  return Plugin_Handled;
}

public int GetSidesRoundWinner() {
  int ctAlive = CountAlivePlayersOnTeam(CS_TEAM_CT);
  int tAlive = CountAlivePlayersOnTeam(CS_TEAM_T);
  int winningCSTeam = CS_TEAM_NONE;
  LogDebug("GetSidesRoundWinner: ctAlive=%d, tAlive=%d", ctAlive, tAlive);
  if (ctAlive > tAlive) {
    winningCSTeam = CS_TEAM_CT;
  } else if (tAlive > ctAlive) {
    winningCSTeam = CS_TEAM_T;
  } else {
    int ctHealth = SumHealthOfTeam(CS_TEAM_CT);
    int tHealth = SumHealthOfTeam(CS_TEAM_T);
    LogDebug("GetSidesRoundWinner: ctHealth=%d, tHealth=%d", ctHealth, tHealth);
    if (ctHealth > tHealth) {
      winningCSTeam = CS_TEAM_CT;
    } else if (tHealth > ctHealth) {
      winningCSTeam = CS_TEAM_T;
    } else {
      LogDebug("GetSidesRoundWinner: Falling to random knife winner");
      if (GetRandomFloat(0.0, 1.0) < 0.5) {
        winningCSTeam = CS_TEAM_CT;
      } else {
        winningCSTeam = CS_TEAM_T;
      }
    }
  }

  return winningCSTeam;
}
