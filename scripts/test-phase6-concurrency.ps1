$ErrorActionPreference = 'Stop'
$db = 'supabase_db_juridico-sync'
$office = 'a6000000-0000-4000-9000-000000000001'
$lawyer = 'a6000000-0000-4000-8000-000000000001'
$operator = 'a6000000-0000-4000-8000-000000000002'
$lawyer2 = 'a6000000-0000-4000-8000-000000000003'
$clientParty = 'a6000000-0000-4000-a000-000000000001'
$relatedParty = 'a6000000-0000-4000-a000-000000000002'
$client = 'a6000000-0000-4000-b000-000000000001'

function Invoke-Psql([string]$sql) {
  $output = $sql | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  $last = @($output | Where-Object { $_ -and $_.ToString().Trim() } | Select-Object -Last 1)
  if ($last.Count -eq 0) { return '' }
  return $last[0].ToString().Trim()
}

Invoke-Psql @"
delete from public.process_party where office_id = '$office';
delete from public.legal_process where office_id = '$office';
delete from public.process_import_preview where office_id = '$office';
insert into auth.users(id,email) values
 ('$lawyer','phase6-concurrency-lawyer@example.test'),
 ('$operator','phase6-concurrency-operator@example.test'),
 ('$lawyer2','phase6-concurrency-lawyer2@example.test')
on conflict do nothing;
insert into public.office(id,name,is_active) values ('$office','Phase 6 Concurrency Office',true) on conflict do nothing;
insert into public.user_profile(id,office_id,name,role,is_owner,is_active) values
 ('$lawyer','$office','Phase 6 Lawyer','lawyer',true,true),
 ('$operator','$office','Phase 6 Operator','operator',false,true),
 ('$lawyer2','$office','Phase 6 Lawyer 2','lawyer',false,true)
on conflict (id) do nothing;
insert into public.party(id,office_id,party_type,display_name,normalized_name,created_by) values
 ('$clientParty','$office','person','Phase 6 Concurrency Client','phase 6 concurrency client','$lawyer'),
 ('$relatedParty','$office','person','Phase 6 Concurrency Related','phase 6 concurrency related','$lawyer')
on conflict (id) do nothing;
insert into public.client(id,office_id,party_id,created_by) values ('$client','$office','$clientParty','$lawyer') on conflict do nothing;
"@

function Invoke-AsActor([string]$actor, [string]$sql) {
  return "begin; set local role authenticated; select set_config('request.jwt.claim.sub','$actor',true); $sql commit;"
}

$createCnj = '0004453-12.2026.8.16.0000'
$createSql = "select public.create_legal_process('$client','$createCnj','TJPR','PJe',true);"
$createFile1 = Join-Path ([System.IO.Path]::GetTempPath()) 'phase6-create-1.sql'
$createFile2 = Join-Path ([System.IO.Path]::GetTempPath()) 'phase6-create-2.sql'
Set-Content $createFile1 (Invoke-AsActor $lawyer $createSql) -Encoding UTF8
Set-Content $createFile2 (Invoke-AsActor $operator $createSql) -Encoding UTF8
$createJob1 = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$createFile1
$createJob2 = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$createFile2
Wait-Job $createJob1,$createJob2 | Out-Null
$createOut1 = (Receive-Job $createJob1) -join ' '
$createOut2 = (Receive-Job $createJob2) -join ' '
Remove-Job $createJob1,$createJob2 -Force
Remove-Item $createFile1,$createFile2 -Force
$createCount = Invoke-Psql "select count(*) from public.legal_process where office_id='$office' and cnj_number='00044531220268160000';"
$createErrors = @($createOut1,$createOut2 | Where-Object {$_ -match 'ERROR'})
$createSuccesses = @($createOut1,$createOut2 | Where-Object {$_ -notmatch 'ERROR' -and $_ -match '[0-9a-f-]{36}'})
if ($createCount -ne '1' -or $createErrors.Count -ne 1 -or $createSuccesses.Count -ne 1) { throw "Duplicate create assertion failed: count=$createCount errors=$($createErrors.Count) successes=$($createSuccesses.Count) out1=$createOut1 out2=$createOut2" }

$previewRows = '[{"cnj_number":"0008569-61.2026.8.16.0000","client_id":"' + $client + '","tribunal":"TJPR","system":"PJe","party_id":null,"role_in_process":null,"is_public":true,"monitoring_status":"paused","notes":null,"source":"csv"}]'
$summary = '{"total_rows":1}'
$previewSql = "select preview_id from public.preview_process_import('$previewRows'::jsonb, repeat('b',64), 'phase6-csv-v1', '$summary'::jsonb);"
$previewId = Invoke-Psql (Invoke-AsActor $lawyer $previewSql)
$confirmFile1 = Join-Path ([System.IO.Path]::GetTempPath()) 'phase6-preview-confirm-1.sql'
$confirmFile2 = Join-Path ([System.IO.Path]::GetTempPath()) 'phase6-preview-confirm-2.sql'
$confirmSql = "select public.confirm_process_import('$previewId');"
Set-Content $confirmFile1 (Invoke-AsActor $lawyer $confirmSql) -Encoding UTF8
Set-Content $confirmFile2 (Invoke-AsActor $operator $confirmSql) -Encoding UTF8
$confirmJob1 = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$confirmFile1
$confirmJob2 = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$confirmFile2
Wait-Job $confirmJob1,$confirmJob2 | Out-Null
$confirmOut1 = (Receive-Job $confirmJob1) -join ' '
$confirmOut2 = (Receive-Job $confirmJob2) -join ' '
Remove-Job $confirmJob1,$confirmJob2 -Force
Remove-Item $confirmFile1,$confirmFile2 -Force
$previewProcessCount = Invoke-Psql "select count(*) from public.legal_process where office_id='$office' and cnj_number='00085696120268160000';"
$previewAuditCount = Invoke-Psql "select count(*) from public.audit_log where office_id='$office' and action='process.imported' and entity_id='$previewId';"
if ($previewProcessCount -ne '1' -or $previewAuditCount -ne '1' -or ($confirmOut1 + $confirmOut2) -match 'duplicate key') { throw "Preview confirmation assertion failed: process_count=$previewProcessCount audit_count=$previewAuditCount out1=$confirmOut1 out2=$confirmOut2" }

$relationProcess = Invoke-Psql (Invoke-AsActor $lawyer "select public.create_legal_process('$client','0002557-31.2026.8.16.0000','TJPR','PJe',true);")
$relationId = Invoke-Psql (Invoke-AsActor $lawyer "select public.create_process_party('$relationProcess','$relatedParty','plaintiff','manual',null);")
$terminalFile1 = Join-Path ([System.IO.Path]::GetTempPath()) 'phase6-terminal-confirm.sql'
$terminalFile2 = Join-Path ([System.IO.Path]::GetTempPath()) 'phase6-terminal-reject.sql'
Set-Content $terminalFile1 (Invoke-AsActor $lawyer "select public.confirm_process_party('$relationId');") -Encoding UTF8
Set-Content $terminalFile2 (Invoke-AsActor $lawyer2 "select public.reject_process_party('$relationId');") -Encoding UTF8
$terminalJob1 = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$terminalFile1
$terminalJob2 = Start-Job -ScriptBlock { param($db,$file) Get-Content $file | docker exec -i $db psql -qAt -U postgres -d postgres 2>&1 } -ArgumentList $db,$terminalFile2
Wait-Job $terminalJob1,$terminalJob2 | Out-Null
$terminalOut1 = (Receive-Job $terminalJob1) -join ' '
$terminalOut2 = (Receive-Job $terminalJob2) -join ' '
Remove-Job $terminalJob1,$terminalJob2 -Force
Remove-Item $terminalFile1,$terminalFile2 -Force
$terminalResult = Invoke-Psql "select confirmation_status || '|' || (select count(*) from public.audit_log where office_id='$office' and entity_id='$relationId' and action in ('process_party.confirmed','process_party.rejected')) from public.process_party where id='$relationId';"
if ($terminalResult -notmatch '^(confirmed|rejected)\|1$' -or ($terminalOut1 + $terminalOut2) -notmatch 'invalid transition') { throw "Terminal race assertion failed: result=$terminalResult confirm=$terminalOut1 reject=$terminalOut2" }

Write-Output "create_same_cnj=count:$createCount one_success_one_conflict=true"
Write-Output "confirm_same_preview=processes:$previewProcessCount imported_audits:$previewAuditCount replay_safe=true"
Write-Output "confirm_vs_reject=$terminalResult one_success_one_invalid_transition=true"
