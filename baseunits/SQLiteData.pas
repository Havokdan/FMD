unit SQLiteData;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, LazFileUtils, strutils, sqlite3conn, sqldb;

type

  { TSQLite3ConnectionH }

  TSQLite3ConnectionH = class(TSQLite3Connection)
  public
    property Handle read GetHandle;
  end;

  TExceptionEvent = procedure(Sender: TObject; E: Exception) of object;

  { TSQliteData }

  TSQliteData = class
  private
    FConn: TSQLite3ConnectionH;
    FOnError: TExceptionEvent;
    FTrans: TSQLTransaction;
    FQuery: TSQLQuery;
    FFilename: String;
    FTableName: String;
    FCreateParams: String;
    FSelectParams: String;
    FRecordCount: Integer;
    procedure DoOnError(E: Exception);
    function GetAutoApplyUpdates: Boolean;
    procedure SetAutoApplyUpdates(AValue: Boolean);
    procedure SetCreateParams(AValue: String);
    procedure SetOnError(AValue: TExceptionEvent);
    procedure SetSelectParams(AValue: String);
  protected
    function OpenDB: Boolean; virtual;
    function CreateDB: Boolean; virtual;
    function ConvertNewTableIF: Boolean; virtual;
    procedure DoConvertNewTable;
    procedure GetRecordCount; virtual;
    procedure SetRecordCount(const AValue: Integer); virtual;
    procedure IncRecordCount(const N: Integer = 1);
    procedure Vacuum; virtual;
  public
    constructor Create;
    destructor Destroy; override;
    function Open(const AOpenTable: Boolean = True): Boolean;
    function OpenTable: Boolean; virtual;
    procedure Close;
    procedure CloseTable;
    procedure Refresh(RecheckDataCount: Boolean = False);
    procedure Commit; virtual;
    procedure CommitRetaining; virtual;
    procedure Save;
    function Connected: Boolean; inline;
    property Connection: TSQLite3ConnectionH read FConn;
    property Transaction: TSQLTransaction read FTrans;
    property Table: TSQLQuery read FQuery;
    property Filename: String read FFilename write FFilename;
    property TableName: String read FTableName write FTableName;
    property CreateParams: String read FCreateParams write SetCreateParams;
    property SelectParams: String read FSelectParams write SetSelectParams;
    property RecordCount: Integer read FRecordCount;
    property AutoApplyUpdates: Boolean read GetAutoApplyUpdates write SetAutoApplyUpdates;
    property OnError: TExceptionEvent read FOnError write SetOnError;
  end;

  function QuotedStrd(const S: string): string; inline;

implementation

function QuotedStrd(const S: string): string;
begin
  Result := AnsiQuotedStr(S, '"');
end;

{ TSQliteData }

procedure TSQliteData.DoOnError(E: Exception);
begin
  if Assigned(OnError) then
    OnError(Self, E);
end;

function TSQliteData.GetAutoApplyUpdates: Boolean;
begin
  Result := sqoAutoApplyUpdates in FQuery.Options;
end;

procedure TSQliteData.SetAutoApplyUpdates(AValue: Boolean);
begin
  if AValue then
    FQuery.Options := FQuery.Options + [sqoAutoApplyUpdates]
  else
    FQuery.Options := FQuery.Options - [sqoAutoApplyUpdates];
end;

procedure TSQliteData.SetCreateParams(AValue: String);
begin
  if FCreateParams = AValue then Exit;
  FCreateParams := TrimSet(Trim(AValue), ['(', ')', ';']);
end;

procedure TSQliteData.SetOnError(AValue: TExceptionEvent);
begin
  if FOnError = AValue then Exit;
  FOnError := AValue;
end;

procedure TSQliteData.SetSelectParams(AValue: String);
begin
  if FSelectParams = AValue then Exit;
  FSelectParams := AValue;
end;

function TSQliteData.OpenDB: Boolean;
begin
  Result := False;
  if FFilename = '' then Exit;
  try
    FConn.DatabaseName := FFilename;
    FConn.Connected := True;
    FTrans.Active := True;
  except
  end;
  Result := FConn.Connected;
end;

function TSQliteData.CreateDB: Boolean;
begin
  Result := False;
  if (FTableName = '') or (FCreateParams = '') then Exit;
  if not FConn.Connected then
    if not OpenDB then Exit;
  try
    FConn.ExecuteDirect('DROP TABLE IF EXISTS ' + QuotedStrd(FTableName));
    FConn.ExecuteDirect('CREATE TABLE ' + QuotedStrd(FTableName) + #13#10 +
      '(' + FCreateParams + ')');
    FTrans.Commit;
    Result := True;
  except
  end;
end;

function TSQliteData.ConvertNewTableIF: Boolean;
begin
  Result := False;
end;

procedure TSQliteData.DoConvertNewTable;
var
  qactive: Boolean;
begin
  if not ConvertNewTableIF then Exit;
  if not FConn.Connected then Exit;
  try
    qactive := FQuery.Active;
    if FQuery.Active then FQuery.Close;
    with FConn do
    begin
      ExecuteDirect('DROP TABLE IF EXISTS ' + QuotedStrd('temp' + FTableName));
      ExecuteDirect('CREATE TABLE ' + QuotedStrd('temp' + FTableName) + #13#10 + FCreateParams);
      ExecuteDirect('INSERT INTO ' + QuotedStrd('temp' + FTableName) + ' SELECT * FROM ' +
        QuotedStrd(FTableName));
      ExecuteDirect('DROP TABLE ' + QuotedStrd(FTableName));
      ExecuteDirect('ALTER TABLE ' + QuotedStrd('temp' + FTableName) + ' RENAME TO ' +
        QuotedStrd(FTableName));
    end;
    FTrans.Commit;
    if qactive <> FQuery.Active then
      FQuery.Active := qactive;
  except
    FTrans.Rollback;
  end;
end;

procedure TSQliteData.GetRecordCount;
begin
  if FQuery.Active then
  begin
    FQuery.Last;
    FRecordCount := FQuery.RecordCount;
    FQuery.Refresh;
  end
  else FRecordCount := 0;
end;

procedure TSQliteData.SetRecordCount(const AValue: Integer);
begin
  if FRecordCount = AValue then Exit;
  FRecordCount := AValue;
end;

procedure TSQliteData.IncRecordCount(const N: Integer);
begin
  Inc(FRecordCount, N);
end;

procedure TSQliteData.Vacuum;
var
  qactive: Boolean;
begin
  if not FConn.Connected then Exit;
  try
    qactive := FQuery.Active;
    if FQuery.Active then FQuery.Close;
    FConn.ExecuteDirect('END TRANSACTION');
    try
      FConn.ExecuteDirect('VACUUM');
    finally
      FConn.ExecuteDirect('BEGIN TRANSACTION');
      if FQuery.Active <> qactive then
        FQuery.Active := qactive;
    end;
  except
    on E: Exception do
      DoOnError(E);
  end;
end;

constructor TSQliteData.Create;
begin
  FConn := TSQLite3ConnectionH.Create(nil);
  FTrans := TSQLTransaction.Create(nil);
  FQuery := TSQLQuery.Create(nil);
  FConn.CharSet := 'UTF8';
  FConn.Transaction := FTrans;
  FQuery.DataBase := FTrans.DataBase;
  FQuery.Transaction := FTrans;
  AutoApplyUpdates := True;
  FRecordCount := 0;
  FFilename := '';
  FTableName := 'maintable';
  FCreateParams := '';
end;

destructor TSQliteData.Destroy;
begin
  Self.Close;
  FConn.Free;
  FQuery.Free;
  FTrans.Free;
  inherited Destroy;
end;

function TSQliteData.Open(const AOpenTable: Boolean): Boolean;
begin
  Result := False;
  if (FFilename = '') or (FCreateParams = '') then Exit;
  if FileExistsUTF8(FFilename) then
    Result := OpenDB
  else
    Result := CreateDB;
  if Result and AOpenTable then
    Result := OpenTable;
end;

function TSQliteData.OpenTable: Boolean;
begin
  Result := False;
  if not FConn.Connected then Exit;
  try
    if FQuery.Active then FQuery.Close;
    if FSelectParams <> '' then
      FQuery.SQL.Text := FSelectParams
    else
      FQuery.SQL.Text := 'SELECT * FROM ' + QuotedStrd(FTableName);
    FQuery.Open;
    GetRecordCount;
  except
    on E: Exception do
      DoOnError(E);
  end;
  Result := FQuery.Active;
  if Result then DoConvertNewTable;
end;

procedure TSQliteData.Close;
begin
  if not FConn.Connected then Exit;
  try
    Save;
    Vacuum;
    CloseTable;
    FTrans.Active := False;
    FConn.Close;
  except
    on E: Exception do
      DoOnError(E);
  end;
end;

procedure TSQliteData.CloseTable;
begin
  if not FConn.Connected then Exit;
  if not FQuery.Active then Exit;
  try
    FQuery.Close;
    FRecordCount := 0;
  except
    on E: Exception do
      DoOnError(E);
  end;
end;

procedure TSQliteData.Refresh(RecheckDataCount: Boolean);
begin
  if not FConn.Connected then Exit;
  if FQuery.Active then
    FQuery.Refresh
  else
    FQuery.Open;
  if RecheckDataCount then
    GetRecordCount;
end;

procedure TSQliteData.Commit;
begin
  if not FConn.Connected then Exit;
  try
    Transaction.Commit;
  except
    Transaction.Rollback;
  end;
end;

procedure TSQliteData.CommitRetaining;
begin
  if not FConn.Connected then Exit;
  try
    Transaction.CommitRetaining;
  except
    Transaction.RollbackRetaining;
  end;
end;

procedure TSQliteData.Save;
var
  qactive: Boolean;
begin
  if not FConn.Connected then Exit;
  try
    qactive := FQuery.Active;
    if FQuery.Active then
    begin
      FQuery.ApplyUpdates;
      FQuery.Close;
    end;
    FTrans.Commit;
    if qactive <> qactive then
      FQuery.Active := FQuery.Active;
    if FQuery.Active then
      GetRecordCount;
  except
    on E: Exception do
      DoOnError(E);
  end;
end;

function TSQliteData.Connected: Boolean;
begin
  Result := FConn.Connected and FQuery.Active;
end;

end.
