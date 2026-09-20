{
  ==============================================================================
   NPC Replacer Converter.pas
  ==============================================================================

   Description:
     This script is part of the "NPC Replacer Converter" toolset.
     It functions as the *Config Generator (ConfigGen)* phase, executed after
     the Isolator. Its purpose is to create configuration files for
     **SkyPatcher**, **Race Distribution Framework (RDF)**, or **Recast** based
     on user-selected options and NPC record data gathered from the list of
     plugins currently loaded in xEdit.

   Features:
     - Integrates seamlessly with the Isolator phase (optional).
     - Prompts user to select output framework (SkyPatcher / RDF / Recast)
       and generation options via checkboxes.
     - Scans and compares NPC records (original vs. replacer) to determine
       which parameters (appearance, gender, name, etc.) should be replaced.
     - Generates structured `.ini` (SkyPatcher), `.txt` (RDF), or `.toml` (Recast)
       config files.
     - Automatically comments out or enables settings according to user preferences.

   Usage:
     1. Run this script in xEdit (SSEEdit) on your replacer plugin.
     2. Select whether to run in Integration Mode (to invoke Isolator).
     3. Choose your config generation target (SkyPatcher / RDF / Recast).
     4. Select desired options in the checklist dialog.
     5. The script will process NPC records and output a ready-to-use config file.

   Notes:
      - Intended for Skyrim SE/AE with SkyPatcher, RDF, and Recast support.
      - Uses `NPC Replacer Isolator.pas` when Integration Mode is selected.
      - This script can also be run standalone if the Isolator Process has already been applied.
      - Compatible with both FormID- and EditorID-based reference methods.
      - Recast does not support Race replacement or Outfit output.

   Author:mmsk4989
   Version: 2.3.0
   Last Updated: [2026-05-03]

   Changelog:
     - Changed Force Replace XXX option behavior:
       When OFF: Do not output the setting line
       When ON: Output the setting line with comparison logic (same as before)
     - Added Outfit setting output option
  ==============================================================================
}

unit NPCReplacerConverter;

uses 'NPC Replacer Isolator';
uses 'xEdit_mmskCommonLibrary\xEdit_mmskCommonLibrary';

const
  USE_EDITOR_ID = false;

var
  // 設定ファイル出力用変数
  slExport, slCommentOut: TStringList;
  coChar, targetFileName, replacerFileName: string;

  // イニシャライズ処理で設定・使用する変数
  callIsolator, useFormID, disableAll, replaceVS: boolean;

  // 選択中のフレームワーク ('SkyPatcher' / 'RDF' / 'Recast')
  framework: string;

  // Output フラグ - ONの場合のみ該当の設定行を出力する
  outputSkin, outputRace, outputGender, outputName, outputVoiceType, outputOutfit: boolean;

function GenerateVisualStyleString(const targetID, replacerID, fw: string): string;
begin
  Result := '';
  if fw = 'SkyPatcher' then
    Result := 'filterByNpcs=' + TargetID + ':copyVisualStyle=' + ReplacerID
  else if fw = 'Recast' then
    Result := 'face = "' + ReplacerID + '"'
  else
    Result := 'match=' + TargetID + ' swap=' + ReplacerID;
end;

// フレームワーク選択（チェックボックス方式、排他制御あり）
// 複数選択された場合はエラーを表示して再選択させる
function SelectFramework: string;
var
  opts, disableOpts: TStringList;
  skyPatcherSelected, rdfSelected, recastSelected: Boolean;
  selectedCount: Integer;
begin
  Result := '';
  opts := TStringList.Create;
  disableOpts := TStringList.Create;
  try
    opts.Values['SkyPatcher'] := 'False';
    opts.Values['RDF (Race Distribution Framework)'] := 'False';
    opts.Values['Recast'] := 'False';

    if not ShowCheckboxForm(opts, disableOpts, 'Select Framework (choose only one)') then begin
      AddMessage('Selection was canceled.');
      Exit;
    end;

    skyPatcherSelected := GetBoolSLValue(opts.Values['SkyPatcher']);
    rdfSelected        := GetBoolSLValue(opts.Values['RDF (Race Distribution Framework)']);
    recastSelected     := GetBoolSLValue(opts.Values['Recast']);

    selectedCount := 0;
    if skyPatcherSelected then Inc(selectedCount);
    if rdfSelected then Inc(selectedCount);
    if recastSelected then Inc(selectedCount);
    // AddMessage('Selected Count: ' + IntToStr(selectedCount));

    // 複数選択された場合はエラーを表示して再選択させる
    if selectedCount > 1 then begin
      MessageDlg('Please select only one framework.', mtError, [mbOK], 0);
      Result := SelectFramework; // 再選択
      Exit;
    end;

    // 何も選択されなかった場合もエラーを表示して再選択させる
    if selectedCount = 0 then begin
      MessageDlg('Please select a framework.', mtError, [mbOK], 0);
      Result := SelectFramework; // 再選択
      Exit;
    end;

    if skyPatcherSelected then
      Result := 'SkyPatcher'
    else if rdfSelected then
      Result := 'RDF'
    else if recastSelected then
      Result := 'Recast';

  finally
    opts.Free;
    disableOpts.Free;
  end;
end;

procedure InsertRecastManifest;
begin
  if framework = 'Recast' then begin
    slExport.Insert(0, '');
    slExport.Insert(0, 'api_version = 1');
    slExport.Insert(0, 'priority = 100');
    slExport.Insert(0, 'name = "' + replacerFileName + '"');
    slExport.Insert(0, '[manifest]');
  end;
end;

function Initialize: integer;
var
  validInput: boolean;
  opts, disableOpts: TStringList;
  checkBoxCaption: string;
  i: Integer;
begin
  slExport            := TStringList.Create;
  slCommentOut        := TStringList.Create;
  coChar              := '';

  callIsolator        := false;
  useFormID           := false;

  disableAll          := false;
  replaceVS           := false;

  // Output setting オプションのデフォルト値を設定
  outputSkin          := false;
  outputRace          := false;
  outputGender        := false;
  outputName          := false;
  outputVoiceType     := false;
  outputOutfit        := false;
  opts                := TStringList.Create;
  disableOpts         := TStringList.Create;

  checkBoxCaption := '';

  Result              := 0;

  if MessageDlg(
    'Run in Integration Mode?' + #13#10 +
    'Yes = Run with Isolator Process' + #13#10 +
    'No = Run Converter only', mtConfirmation, [mbYes, mbNo], 0
    ) = mrYes then
    callIsolator := true;

  // フレームワーク選択（チェックボックス方式、排他制御あり）
  framework := SelectFramework;
  if framework = '' then begin
    AddMessage('Framework selection was canceled.');
    Result := -1;
    Exit;
  end;

  AddMessage('Selected framework: ' + framework);

  // フレームワークの種類に応じてコメントアウト文字を切り替え
  // TOML形式のRecastは '#' を使用、SkyPatcherは ';' を使用
  if framework = 'SkyPatcher' then
    coChar := ';'
  else
    coChar := '#';

  //コメントアウト文字列リストの初期化
  slCommentOut.Values['CopyVS']    := '';
  slCommentOut.Values['Skin']      := '';
  slCommentOut.Values['Race']      := '';
  slCommentOut.Values['Gender']    := '';
  slCommentOut.Values['Name']      := '';
  slCommentOut.Values['VoiceType'] := '';
  slCommentOut.Values['Outfit']    := '';

  if framework = 'SkyPatcher' then
    checkBoxCaption := '  Choose SkyPatcher Option'
  else if framework = 'Recast' then
    checkBoxCaption := '  Choose Recast Option'
  else
    checkBoxCaption := '  Choose RDF Option';

  if callIsolator then begin
    if RunIsolatorInitialize = -1 then begin
      Result := -1;
      Exit;
    end;
  end;

  // 各オプションの設定
  try
    opts.Values['Use Form ID for config file output'] := 'False';
    opts.Values['Disable the config file by default'] := 'False';
    opts.Values['Replace Visual Style']               := 'False';
    opts.Values['Output Skin or body setting']        := 'False';
    opts.Values['Output Race setting']                := 'False';
    opts.Values['Output Gender setting']              := 'False';
    opts.Values['Output Name setting']                := 'False';
    opts.Values['Output VoiceType setting']           := 'False';
    opts.Values['Output Outfit setting']              := 'False';

    if framework = 'SkyPatcher' then begin
      opts.Values['Replace Visual Style'] := 'True';
      opts.Values['Output Skin or body setting']         := 'True';
    end
    else if framework = 'Recast' then begin
      opts.Values['Replace Visual Style'] := 'True';
      opts.Values['Output Skin or body setting']         := 'True';
      // RecastはRaceとOutfitに未対応のため無効化
      disableOpts.Add('Output Race setting');
      disableOpts.Add('Output Outfit setting');
    end
    else begin
      // RDFはSkyPatcher専用オプションを無効化
      disableOpts.Add('Replace Visual Style');
      disableOpts.Add('Output Skin or body setting');
      disableOpts.Add('Output Race setting');
      disableOpts.Add('Output Gender setting');
      disableOpts.Add('Output Name setting');
      disableOpts.Add('Output VoiceType setting');
      disableOpts.Add('Output Outfit setting');
    end;

    if ShowCheckboxForm(opts, disableOpts, checkBoxCaption) then
    begin
      AddMessage('You selected:');
      for i := 0 to opts.Count - 1 do
        AddMessage('  ' + opts.Names[i] + ' - ' + opts.ValueFromIndex[i]);
    end
    else begin
      AddMessage('Selection was canceled.');
      Result := -1;
      Exit;
    end;

    // 出力ファイルに使うのはFormIDとEditorIDのどちらか
    useFormID := GetBoolSLValue(opts.Values['Use Form ID for config file output']);

    // 出力ファイルの記述をすべてコメントアウトするか
    disableAll := GetBoolSLValue(opts.Values['Disable the config file by default']);

    // SkyPatcher、Recast利用時のオプション設定
    replaceVS       := GetBoolSLValue(opts.Values['Replace Visual Style']);    // 見た目を変更するか
    outputSkin      := GetBoolSLValue(opts.Values['Output Skin or body setting']);            // 肌を変更するか

    // 各設定行を出力するかどうか（ONの場合のみ出力）
    outputRace      := GetBoolSLValue(opts.Values['Output Race setting']);
    outputGender    := GetBoolSLValue(opts.Values['Output Gender setting']);
    outputName      := GetBoolSLValue(opts.Values['Output Name setting']);
    outputVoiceType := GetBoolSLValue(opts.Values['Output VoiceType setting']);
    outputOutfit    := GetBoolSLValue(opts.Values['Output Outfit setting']);

    // オプションの選択に応じて、設定行をコメントアウトする
    if disableAll then begin
      slCommentOut.Values['CopyVS']    := coChar;
      slCommentOut.Values['Skin']      := coChar;
      slCommentOut.Values['Race']      := coChar;
      slCommentOut.Values['Gender']    := coChar;
      slCommentOut.Values['Name']      := coChar;
      slCommentOut.Values['VoiceType'] := coChar;
      slCommentOut.Values['Outfit']    := coChar;
    end
    else begin
      // RDF以外（SkyPatcher・Recast）はReplace Visual Style/Skinトグルに連動
      if (framework <> 'RDF') and not replaceVS then
        slCommentOut.Values['CopyVS'] := coChar;

      if not outputSkin then
        slCommentOut.Values['Skin'] := coChar;
    end;

  finally
    opts.Free;
    disableOpts.Free;
  end;
  AddMessage('Config Generator Initialize Finish.');
end;

function Process(e: IInterface): integer;

var
  // replacerFlags, targetFlags: IInterface; // 今は未使用だが今後利用する可能性はある変数なので残しておく。
  replacerNPCIsFemale, targetNPCIsFemale, useTraits: boolean; // NPCフラグ格納用
  replacerName, targetName: string;
  replacerRecord, replacerRaceRecord, replacerVoiceTypeRecord, replacerOutfitRecord: IwbMainRecord;
  targetRecord, targetRaceRecord, targetVoiceTypeRecord, targetOutfitRecord: IwbMainRecord;
  replacerFormIDNative, targetFormIDNative, underscorePos: Cardinal;
  originalTargetID, recordSignature, targetFormIDHex, replacerFormIDHex, targetEditorID, replacerEditorID: string; // レコードID関連
  localTargetFormID, localReplacerFormID,
  trimedTargetFormID, trimedReplacerFormID,
  paddedTargetFormID, paddedReplacerFormID: string; // FormIDを記入用に加工した文字列
  exportTargetID, exportReplacerID, wnamID, exportSkinID, exportRace, exportGender,
  exportName, exportVoiceType, exportOutfit: string; // SkyPatcher, Recast設定ファイルの記入用

begin
  targetFormIDHex    := '';
  targetEditorID  := '';
  replacerFormIDHex    := '';
  replacerEditorID  := '';

  recordSignature := 'NPC_';


  // NPCレコードでなければスキップ
  if Signature(e) <> 'NPC_' then begin
    //AddMessage(EditorID(e) + ' is not NPC record.');
    Exit;
  end;

  // リプレイサーMod名を取得
  replacerFileName := GetFileName(GetFile(e));

  if callIsolator then
    Result := RunIsolatorProcess(e, replacerRecord)
  else
    replacerRecord := e;

  // リプレイサーNPCのForm ID, Editor IDを取得
  replacerFormIDNative := GetElementNativeValues(replacerRecord, 'Record Header\FormID');
  replacerFormIDHex := IntToHex64(replacerFormIDNative, 8);
   //AddMessage('Replacer Form ID: ' + IntToStr(replacerFormID));
   //AddMessage('Replacer Form ID: ' + IntToHex(replacerFormID, 8));
  replacerEditorID := EditorID(replacerRecord);
  // AddMessage('Replacer Editor ID: ' + replacerEditorID);

  // リプレイサーNPCのEditor IDからオリジナルのEditor IDを取得
  underscorePos := Pos('_', replacerEditorID);
  originalTargetID := Copy(replacerEditorID, underscorePos + 1, Length(replacerEditorID) - underscorePos);

  // オリジナルのEditor IDからターゲットNPCのレコードを取得
  AddMessage('Searching for target record...');
  targetRecord := FindRecordByRecordID(originalTargetID, 'NPC_', USE_EDITOR_ID);

  if not Assigned(targetRecord) then begin
    AddMessage('Target record not found. Processing will be skipped.');
    Exit;
  end;
  AddMessage('Found record: ' + Name(targetRecord));
  targetFileName := GetFileName(targetRecord);
  //AddMessage('Target file name set to: ' + targetFileName);

  // ターゲットNPCのFormID,EditorIDを取得
  //targetFormID := IntToHex64(GetElementNativeValues(targetRecord, 'Record Header\FormID'), 8);
  targetFormIDNative := GetElementNativeValues(targetRecord, 'Record Header\FormID');
  targetFormIDHex := IntToHex64(targetFormIDNative, 8);
    //AddMessage('Target Record Form ID: ' + targetFormID);
  targetEditorID := EditorID(targetRecord);
    //AddMessage('Target Record Editor ID: ' + targetEditorID);

  // リプレイサーNPCのフラグ、種族、名前、音声タイプ、装備を取得
  //replacerFlags            := ElementByPath(replacerRecord, 'ACBS - Configuration');
  replacerNPCIsFemale     := IsNPCFemale(replacerRecord);
  replacerName            := GetElementEditValues(replacerRecord, 'FULL');
  replacerRaceRecord      := GetLinkedMasterRecord(replacerRecord, 'RNAM');
  replacerVoiceTypeRecord := GetLinkedMasterRecord(replacerRecord, 'VTCK');
  replacerOutfitRecord    := GetLinkedMasterRecord(replacerRecord, 'DOFT');

  // レコードがuse traitsフラグを持っているか確認し、持っていた場合は専用処理に入る
  useTraits := IsNPCUsingTraits(replacerRecord);

  if useTraits then begin
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    AddMessage('  This NPC Record has Use Traits Template Flag. Config generation will be skipped.');
    AddMessage('--------------------------------------------------------------------------------------------------------------------------------------------------');
    Exit;
  end;

  // ターゲットNPCのフラグ、種族、名前、音声タイプ、装備を取得
  //targetFlags            := ElementByPath(targetRecord, 'ACBS - Configuration');
  targetNPCIsFemale     := IsNPCFemale(targetRecord);
  targetName            := GetElementEditValues(targetRecord, 'FULL');
  targetRaceRecord      := GetLinkedMasterRecord(targetRecord, 'RNAM');
  targetVoiceTypeRecord := GetLinkedMasterRecord(targetRecord, 'VTCK');
  targetOutfitRecord    := GetLinkedMasterRecord(targetRecord, 'DOFT');


  // 各設定行の出力が有効かつdisableAllがOFFの場合のみ、比較判定を行う
  // disableAllがONの場合は、Initializeで既に全てコメントアウトに設定済みなので何もしない
  if not disableAll then begin
    // 出力が有効な項目のみコメントアウト判定を行う
    if outputSkin then begin
      slCommentOut.Values['Skin'] := '';
      // 肌が同じ場合はコメントアウト
      if GetElementNativeValues(replacerRecord, 'WNAM') = GetElementNativeValues(targetRecord, 'WNAM') then
        slCommentOut.Values['Skin'] := coChar;
    end;

    if outputRace then begin
      slCommentOut.Values['Race'] := '';
      // 種族が未設定、または種族が同じ場合はコメントアウト
      if not Assigned(replacerRaceRecord) then
        slCommentOut.Values['Race'] := coChar
      else if GetElementNativeValues(replacerRaceRecord, 'Record Header\FormID') = GetElementNativeValues       (targetRaceRecord, 'Record Header\FormID') then
        slCommentOut.Values['Race'] := coChar;
    end;

    if outputGender then begin
      slCommentOut.Values['Gender'] := '';
      // 性別が同じ場合はコメントアウト
      if replacerNPCIsFemale = targetNPCIsFemale then
        slCommentOut.Values['Gender'] := coChar;
    end;

    if outputName then begin
      slCommentOut.Values['Name'] := '';
      // 名前が同じ場合はコメントアウト
      if replacerName = targetName then
        slCommentOut.Values['Name'] := coChar;
    end;

    if outputVoiceType then begin
      slCommentOut.Values['VoiceType'] := '';
      // 音声タイプが未設定、または同じ場合はコメントアウト
      if not Assigned(replacerVoiceTypeRecord) then
        slCommentOut.Values['VoiceType'] := coChar
      else if GetElementNativeValues(replacerVoiceTypeRecord, 'Record Header\FormID') = GetElementNativeValues(targetVoiceTypeRecord, 'Record Header\FormID') then
        slCommentOut.Values['VoiceType'] := coChar;
    end;

    if outputOutfit then begin
      slCommentOut.Values['Outfit'] := '';
      // 衣装が未設定、または同じ場合はコメントアウト
      if not Assigned(replacerOutfitRecord) then
        slCommentOut.Values['Outfit'] := coChar
      else if GetElementNativeValues(replacerOutfitRecord, 'Record Header\FormID') = GetElementNativeValues(targetOutfitRecord, 'Record Header\FormID') then
        slCommentOut.Values['Outfit'] := coChar;
    end;
  end;

  // 出力ファイル用の配列操作
  // FormIDを8桁の16進数文字列に変換し、プラグイン内で有効な値を取り出す
  localTargetFormID := ExtractLocalFormIDHex(targetFormIDHex);
  localReplacerFormID := ExtractLocalFormIDHex(replacerFormIDHex);

  if useFormID then begin
    if framework = 'Recast' then begin
      // Recastはゼロパディングした形式のForm IDを設定、tomlファイルへの記入はこちらを利用する
      paddedTargetFormID := PadLeftZero(localTargetFormID, 8);
      paddedReplacerFormID := PadLeftZero(localReplacerFormID, 8);
    end
    else begin
      // ゼロパディングしない形式のForm IDを設定、Recast以外の設定ファイルはこちらを利用する
      trimedTargetFormID := RemoveLeadingZeros(localTargetFormID);
      trimedReplacerFormID := RemoveLeadingZeros(localReplacerFormID);
    end;

    if framework = 'SkyPatcher' then begin
      exportTargetID := targetFileName + '|' + trimedTargetFormID;
      exportReplacerID := replacerFileName + '|' + trimedReplacerFormID;
      exportRace  := GetFileName(replacerRaceRecord) + '|' + IntToHex(FormID(replacerRaceRecord) and  $FFFFFF, 1);
      exportVoiceType := GetFileName(replacerVoiceTypeRecord) + '|' + IntToHex(FormID(replacerVoiceTypeRecord) and  $FFFFFF, 1);
      exportOutfit := GetFileName(replacerOutfitRecord) + '|' + IntToHex(FormID(replacerOutfitRecord) and  $FFFFFF, 1);
    end
    else if framework = 'Recast' then begin
      //exportTargetID := '0x' + targetFormID + '~' + targetFileName;
      //exportReplacerID := '0x' + replacerFormID + '~' + replacerFileName;
      exportTargetID := '0x' + paddedTargetFormID + '~' + targetFileName;
      exportReplacerID := '0x' + paddedReplacerFormID + '~' + replacerFileName;
      exportRace  := IntToHex(FormID(replacerRaceRecord) and  $FFFFFF, 1) + '~' + GetFileName(replacerRaceRecord);
      exportVoiceType := IntToHex(FormID(replacerVoiceTypeRecord) and  $FFFFFF, 1) + '~' + GetFileName(replacerVoiceTypeRecord);
    end
    else begin
      exportTargetID := trimedTargetFormID + '~' + targetFileName;
      exportReplacerID := trimedReplacerFormID + '~' + replacerFileName;
    end;
  end
  else begin
    exportTargetID := targetEditorID;
    exportReplacerID := replacerEditorID;
    exportRace  := EditorID(replacerRaceRecord);
    exportVoiceType := EditorID(replacerVoiceTypeRecord);
    exportOutfit := EditorID(replacerOutfitRecord);
  end;

  // NPCレコードのWNAMフィールドを取得、設定されていたらWNAMのスキンを反映。
  wnamID := IntToHex(GetElementNativeValues(replacerRecord, 'WNAM') and  $FFFFFF, 1);
  //  AddMessage('wnamID is:' + wnamID);
  if framework = 'SkyPatcher' then begin
    // SkyPatcher:WNAMが設定されていない場合はnullでデフォルトボディを指定。
    if wnamID = '0' then
      exportSkinID := 'null'
    else
      exportSkinID := replacerFileName + '|' + wnamID;

    // 性別フラグの判定
    if replacerNPCIsFemale then
      exportGender := ':setFlags=female'
    else
      exportGender := ':removeFlags=female';
  end
  else if framework = 'Recast' then begin
    // Recast:WNAMにデフォルトボディを指定する方法がないため、未設定の場合はコメントアウトする
    if wnamID = '0' then
      slCommentOut.Values['Skin'] := coChar
    else
      exportSkinID := wnamID + '~' + replacerFileName;

    // 性別フラグの判定
    if replacerNPCIsFemale then
      exportGender := 'female'
    else
      exportGender := 'male';
  end;

  // 名前を入力
  exportName := replacerName;

  // 設定行の見出しとして、ターゲットNPCの名前、FormID、EditorIDを出力する
  slExport.Add(coChar + GetElementEditValues(targetRecord, 'FULL'));
  slExport.Add(coChar + 'Form ID: ' + localTargetFormID + '  Editor ID: ' + targetEditorID);

  if framework = 'SkyPatcher' then begin
    slExport.Add(slCommentOut.Values['CopyVS'] + GenerateVisualStyleString(exportTargetID, exportReplacerID, framework));

    // 各設定行は対応するoutputフラグがONの場合のみ出力
    if outputSkin then
      slExport.Add(slCommentOut.Values['Skin'] + 'filterByNpcs=' + exportTargetID + ':skin=' + exportSkinID);

    if outputRace then
      slExport.Add(slCommentOut.Values['Race'] + 'filterByNpcs=' + exportTargetID + ':race=' + exportRace);

    if outputGender then
      slExport.Add(slCommentOut.Values['Gender'] + 'filterByNpcs=' + exportTargetID + exportGender);

    if outputName then
      slExport.Add(slCommentOut.Values['Name'] + 'filterByNpcs=' + exportTargetID + ':fullName=~' + exportName + '~');

    if outputVoiceType then
      slExport.Add(slCommentOut.Values['VoiceType'] + 'filterByNpcs=' + exportTargetID + ':voiceType=' + exportVoiceType);

    if outputOutfit then
      slExport.Add(slCommentOut.Values['Outfit'] + 'filterByNpcs=' + exportTargetID + ':outfitDefault=' + exportOutfit);
  end
  else if framework = 'Recast' then begin
    slExport.Add('[[npcs]]');
    slExport.Add('target = "' + exportTargetID + '"');
    slExport.Add(slCommentOut.Values['CopyVS'] + GenerateVisualStyleString(exportTargetID, exportReplacerID, framework));

    // 各設定行は対応するoutputフラグがONの場合のみ出力
    if outputSkin then
      slExport.Add(slCommentOut.Values['Skin'] + 'body = "' + exportSkinID + '"');

    // RaceはRecastでは未対応だが、将来的に対応する可能性があるため、コメントとして残しておく
    //if outputRace then
    //  slExport.Add(slCommentOut.Values['Race'] + 'race ="' + exportRace + '"');

    if outputGender then
      slExport.Add(slCommentOut.Values['Gender'] + 'sex = "' + exportGender + '"');

    if outputName then
      slExport.Add(slCommentOut.Values['Name'] +  'name = "' + exportName + '"');

    if outputVoiceType then
      slExport.Add(slCommentOut.Values['VoiceType'] +  'voice = "' + exportVoiceType + '"');

  end
  else if framework = 'RDF' then begin
    slExport.Add(slCommentOut.Values['CopyVS'] + GenerateVisualStyleString(exportTargetID, exportReplacerID, framework));
  end;

  slExport.Add(#13#10);
end;

function Finalize: integer;
var
  dlgSave: TSaveDialog;
  ExportFileName, saveDir, filterString, fileExtension: string;
  existingContent: TStringList;
  userChoice: Integer;
  savedFile:  boolean;
begin
  savedFile := false;

  if callIsolator then
    RunIsolatorFinalize;

  // データがない場合はスキップ
  if slExport.Count = 0 then begin
    slExport.Free;
    Exit;
  end;

  // 出力設定の決定
  if framework = 'SkyPatcher' then begin
    saveDir := DataPath + 'NPC Replacer Converter\SKSE\Plugins\SkyPatcher\npc\NPC Replacer Converter\';
    filterString := 'Ini (*.ini)|*.ini';
    fileExtension := '.ini';
  end
  else if framework = 'Recast' then begin
    saveDir := DataPath + 'NPC Replacer Converter\SKSE\Plugins\Recast\Patches\';
    filterString := 'Toml (*.toml)|*.toml';
    fileExtension := '.toml';
  end
  else if framework = 'RDF' then begin
    saveDir := DataPath + 'NPC Replacer Converter\SKSE\Plugins\RaceSwap\';
    filterString := 'Txt (*.txt)|*.txt';
    fileExtension := '.txt';
  end;

  // ディレクトリ作成
  if not DirectoryExists(saveDir) then
    ForceDirectories(saveDir);

  // ファイル保存
  dlgSave := TSaveDialog.Create(nil);
  try
    dlgSave.Options := dlgSave.Options - [ofOverwritePrompt];
    dlgSave.Filter := filterString;
    dlgSave.InitialDir := saveDir;
    dlgSave.FileName := replacerFileName + fileExtension;
    repeat
      savedFile := false;

      if not dlgSave.Execute then begin
        // ダイアログを閉じたらループ終了
        AddMessage('Save cancelled by user');
        break;
      end
      else begin
        ExportFileName := dlgSave.FileName;

        // ファイルが既に存在するかチェック
        if FileExists(ExportFileName) then begin
          // ユーザーに選択させる
          userChoice := MessageDlg(
            'File already exists: ' + ExtractFileName(ExportFileName) + #13#10 +
            #13#10 +
            'What do you want to do?' + #13#10 +
            #13#10 +
            'Yes: Append to existing file' + #13#10 +
            'No: Overwrite the file' + #13#10 +
            'Cancel: Do not save',
            mtConfirmation,
            [mbYes, mbNo, mbCancel],
            0
          );

          case userChoice of
            mrYes: begin
              // 追記モード
              AddMessage('Appending to ' + ExportFileName);
              existingContent := TStringList.Create;
              try
                existingContent.LoadFromFile(ExportFileName);
                existingContent.AddStrings(slExport);
                existingContent.SaveToFile(ExportFileName);
                AddMessage('Content appended successfully');
              finally
                existingContent.Free;
              end;
              savedFile := true;  // ループを抜ける
            end;

            mrNo: begin
              // 上書きモード
              InsertRecastManifest;
              AddMessage('Overwriting ' + ExportFileName);
              slExport.SaveToFile(ExportFileName);
              AddMessage('File overwritten successfully');
              savedFile := true;  // ループを抜ける
            end;

            mrCancel: begin
              // キャンセル
              AddMessage('Save cancelled');
              savedFile := false;  // ループの開始に戻る
            end;
          end;
        end
        else begin
          // ファイルが存在しない場合は通常通り保存
          InsertRecastManifest;
          AddMessage('Saving ' + ExportFileName);
          slExport.SaveToFile(ExportFileName);
          AddMessage('File saved successfully');
          savedFile := true;  // ループを抜ける
        end;
      end;
    until savedFile;
  finally
    dlgSave.Free;
    slExport.Free;
    slCommentOut.Free;
  end;
end;

end.
