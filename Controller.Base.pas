unit Controller.Base;

interface

uses
  Controller.Interfaces, Horse, FireDAC.Comp.Client, FireDAC.DApt, System.JSON;

type
  TControllerBase = class(TInterfacedObject, IController)
  protected
    function Path: String; virtual;
    function TableName: String; virtual;
    function PrimaryKey: String; virtual;
  private
    App: THorse;
    FQuery: TFDQuery;
    function Location(Codigo: Integer): String;
    function GeneratorValue: Integer;
    function GetJSONArray(JSONString: String): TJSONArray;
    function GetSelectFields(Req: THorseRequest): String;
    procedure Get(Req: THorseRequest; Res: THorseResponse; ANext: TProc);
    procedure GetOne(Req: THorseRequest; Res: THorseResponse; ANext: TProc);
    procedure Post(Req: THorseRequest; Res: THorseResponse; ANext: TProc);
    procedure Put(Req: THorseRequest; Res: THorseResponse; ANext: TProc);
    procedure Delete(Req: THorseRequest; Res: THorseResponse; ANext: TProc);
  public
    constructor Create;
    function Registry(App: THorse; FConn: TFDConnection): IController;
  end;

implementation

uses
  DataSetConverter4D,
  DataSetConverter4D.Impl,
  DataSetConverter4D.Helper,
  DataSetConverter4D.Util,
  Horse.Jhonson, System.SysUtils;

{ TControllerCidades }

constructor TControllerBase.Create;
begin
  FQuery := TFDQuery.Create(nil);
end;

procedure TControllerBase.Delete(Req: THorseRequest; Res: THorseResponse;
  ANext: TProc);
var
  SQL: string;
begin
  SQL := Format('DELETE FROM %s WHERE %s = %s', [TableName, PrimaryKey, Req.Params['id']]);
  FQuery.SQL.Text := SQL;
  FQuery.ExecSQL;
  Res.Status(200);
end;

function TControllerBase.PrimaryKey: String;
begin
  Result := '';
end;

function TControllerBase.GeneratorValue: Integer;
begin
  FQuery.Open(Format('select gen_id(%s, 1) from rdb$database', [PrimaryKey]));
  Result := FQuery.Fields[0].AsInteger;
end;

procedure TControllerBase.Get(Req: THorseRequest; Res: THorseResponse;
  ANext: TProc);
begin
  FQuery.Open(Format('SELECT %s FROM %s', [GetSelectFields(Req), TableName]));
  Res.Send<TJSONArray>(FQuery.AsJSONArray);
end;

function TControllerBase.GetJSONArray(JSONString: String): TJSONArray;
begin
  try
    Result := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(JSONString), 0)
      as TJSONArray;
  except
    Result := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(Format('[%s]', [JSONString])), 0)
      as TJSONArray;
  end;
end;

procedure TControllerBase.GetOne(Req: THorseRequest; Res: THorseResponse;
  ANext: TProc);
begin
  FQuery.Open(Format('SELECT %s FROM %s WHERE %s=%s', [GetSelectFields(Req), TableName, PrimaryKey, Req.Params['id']]));
  Res.Send<TJSONObject>(FQuery.AsJSONObject);
end;

function TControllerBase.GetSelectFields(Req: THorseRequest): String;
var
  sFields: String;
begin
  if Req.Query.TryGetValue('fields', sFields) then
    Result := sFields.Replace('"','').Replace('''', '')
  else
    Result := '*';
end;

function TControllerBase.Location(Codigo: Integer): String;
begin
  Result := Format('%s/%d', [Path, Codigo]);
end;

function TControllerBase.Path: String;
begin
  Result := '';
end;

procedure TControllerBase.Post(Req: THorseRequest; Res: THorseResponse;
  ANext: TProc);
var
  SQL, sCampos, sValues: string;
  jsonObj: TJSONObject;
  jsonArray: TJSONArray;
  I, X: Integer;
  Codigo: Integer;
begin

  jsonArray := GetJSONArray(Req.Body);

  FQuery.Connection.StartTransaction;
  try

    for X := 0 to Pred(jsonArray.Count) do
    begin

      SQL := ''; sCampos := ''; sValues := '';
      jsonObj := jsonArray.Items[X] as TJSONObject;

      for I := 0 to Pred(jsonObj.Count) do
        if sCampos <> '' then
        begin
          sCampos := Format('%s,%s', [sCampos, jsonObj.Pairs[I].JsonString.Value]);
          sValues := Format('%s,%s', [sValues, jsonObj.Pairs[I].ToString.Split([':'])[1]]);
        end
        else
        begin
          sCampos := jsonObj.Pairs[I].JsonString.Value;
          sValues := jsonObj.Pairs[I].ToString.Split([':'])[1];
        end;

      Codigo := GeneratorValue;
      SQL := Format('INSERT INTO %s(%s, %s) VALUES(%d, %s)', [TableName, PrimaryKey, sCampos, Codigo, sValues]);

      FQuery.SQL.Text := SQL.Replace('"', '''');
      FQuery.ExecSQL;

      if THorseHackResponse(Res).GetWebResponse.Location <> '' then
        THorseHackResponse(Res).GetWebResponse.Location :=
          Format('%s;%s', [THorseHackResponse(Res).GetWebResponse.Location, Location(Codigo)])
      else
        THorseHackResponse(Res).GetWebResponse.Location := Location(Codigo);

      if THorseHackResponse(Res).GetWebResponse.CustomHeaders.IndexOfName('ID') <> -1 then
        THorseHackResponse(Res).GetWebResponse.CustomHeaders.Values['ID'] :=
          Format('%s;%s', [THorseHackResponse(Res).GetWebResponse.CustomHeaders.Values['ID'], Codigo.ToString])
      else
        THorseHackResponse(Res).GetWebResponse.CustomHeaders.AddPair('ID', Codigo.ToString);

    end;

    FQuery.Connection.Commit;

  except
    on E: Exception do
    begin
      FQuery.Connection.Rollback;
      raise;
    end;
  end;

  Res.Status(201);

end;

procedure TControllerBase.Put(Req: THorseRequest; Res: THorseResponse;
  ANext: TProc);
var
  SQL, sCampos: string;
  jsonObj: TJSONObject;
  I: Integer;
begin

  jsonObj := TJSONObject.ParseJSONValue(TEncoding.ASCII.GetBytes(Req.Body), 0)
    as TJSONObject;

  SQL := Format('UPDATE %s SET', [TableName]);

  for I := 0 to Pred(jsonObj.Count) do
    if sCampos <> '' then
      sCampos := Format('%s,%s=%s', [sCampos, jsonObj.Pairs[I].JsonString.Value, jsonObj.Pairs[I].ToString.Split([':'])[1]])
    else
      sCampos := Format('%s=%s', [jsonObj.Pairs[I].JsonString.Value, jsonObj.Pairs[I].ToString.Split([':'])[1]]);

  SQL := Format('%s %s WHERE %s=%s', [SQL, sCampos, PrimaryKey, Req.Params['id']]);

  FQuery.SQL.Text := SQL.Replace('"', '''');
  FQuery.ExecSQL;

  Res.Status(200);

end;

function TControllerBase.Registry(App: THorse; FConn: TFDConnection): IController;
begin
  Result := Self;
  FQuery.Connection := FConn;
  App.Get(Path, Get);
  App.Get(Format('%s/:id', [Path]), GetOne);
  App.Post(Path, Post);
  App.Put(Format('%s/:id', [Path]), Put);
  App.Delete(Format('%s/:id', [Path]), Delete);
  Self.App := App;
end;

function TControllerBase.TableName: String;
begin
  Result := '';
end;

end.