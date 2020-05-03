/** Begins the LO3 process. **/
public Action BeginLO3() {
  if (g_GameState == GameState_None)
    return Plugin_Handled;

  ChangeState(GameState_GoingLive);
  Unpause();

  // force kill the warmup if we need to
  if (InWarmup()) {
    EndWarmup();
  }

  // reset player tags
  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      UpdateClanTag(i, true);  // force strip them
    }
  }

  SetConVarInt(FindConVar("sv_cheats"), 0);
  Call_StartForward(g_hOnGoingLive);
  Call_Finish();

  if (GetConVarInt(g_QuickRestartsCvar) == 0) {
    // start lo3
    PugSetup_MessageToAll("%t", "RestartCounter", 1);
    RestartGame(1);
    CreateTimer(1.1, Restart2);
  } else {
    // single restart
    RestartGame(1);
    CreateTimer(1.1, MatchLive);
  }

  return Plugin_Handled;
}

public Action Restart2(Handle timer) {
  if (g_GameState == GameState_None)
    return Plugin_Handled;

  PugSetup_MessageToAll("%t", "RestartCounter", 2);
  RestartGame(1);
  CreateTimer(1.1, Restart3);

  return Plugin_Handled;
}

public Action Restart3(Handle timer) {
  if (g_GameState == GameState_None)
    return Plugin_Handled;

  PugSetup_MessageToAll("%t", "RestartCounter", 3);
  RestartGame(1);
  CreateTimer(1.1, MatchLive);

  return Plugin_Handled;
}

public Action RecordDemoOnLive() {

  if (g_RecordGameOption && !IsTVEnabled()) {
    LogError("GOTV demo could not be recorded since tv_enable is not set to 1");
  } else if (g_RecordGameOption && IsTVEnabled()) {
    // get the map, with any workshop stuff before removed
    // this is {MAP} in the format string
    char mapName[128];
    GetCurrentMap(mapName, sizeof(mapName));
    int last_slash = 0;
    int len = strlen(mapName);
    for (int i = 0; i < len; i++) {
      if (mapName[i] == '/' || mapName[i] == '\\')
        last_slash = i + 1;
    }

    // get the time, this is {TIME} in the format string
    char timeFormat[64];
    g_DemoTimeFormatCvar.GetString(timeFormat, sizeof(timeFormat));
    int timeStamp = GetTime();
    char formattedTime[64];
    FormatTime(formattedTime, sizeof(formattedTime), timeFormat, timeStamp);

    // get the player count, this is {TEAMSIZE} in the format string
    char playerCount[MAX_INTEGER_STRING_LENGTH];
    IntToString(g_PlayersPerTeam, playerCount, sizeof(playerCount));

    // create the actual demo name to use
    char demoName[PLATFORM_MAX_PATH];
    g_DemoNameFormatCvar.GetString(demoName, sizeof(demoName));

    ReplaceString(demoName, sizeof(demoName), "{MAP}", mapName[last_slash], false);
    ReplaceString(demoName, sizeof(demoName), "{TEAMSIZE}", playerCount, false);
    ReplaceString(demoName, sizeof(demoName), "{TIME}", formattedTime, false);

    Call_StartForward(g_hOnStartRecording);
    Call_PushString(demoName);
    Call_Finish();

    if (Record(demoName)) {
      LogMessage("Recording to %s", demoName);
      Format(g_DemoFileName, sizeof(g_DemoFileName), "%s.dem", demoName);
      g_Recording = true;
    }
  }

  return Plugin_Handled;
  
}

public Action MatchLive(Handle timer) {
  if (g_GameState == GameState_None)
    return Plugin_Handled;

  ChangeState(GameState_Live);
  Call_StartForward(g_hOnLive);
  Call_Finish();

  // Restore client clan tags since we're live.
  for (int i = 1; i <= MaxClients; i++) {
    if (IsPlayer(i)) {
      RestoreClanTag(i);
    }
  }

  for (int i = 0; i < 3; i++) {
    PugSetup_MessageToAll("%t", "Live");
  }

  RecordDemoOnLive();

  g_LiveMessageCount = GetConVarInt(FindConVar("mp_freezetime"));
  CreateTimer(1.0, Timer_ShowLiveMessage, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

  return Plugin_Handled;
}

public void ShowLiveMessage() {

  PrintHintTextToAll("%t", "GoLive");

}

public Action Timer_ShowLiveMessage(Handle timer) {
  if (g_GameState != GameState_Live) {
    return Plugin_Stop;
  }

  if (g_LiveMessageCount == 0) {
    return Plugin_Stop;
  }

  g_LiveMessageCount--;
  ShowLiveMessage();

  return Plugin_Continue;

}
