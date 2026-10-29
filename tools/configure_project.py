from pathlib import Path
import json,re
root=Path(__file__).resolve().parents[1]; fpga=root/'fpga'
state=root/'.local_paths.json'
old=json.loads(state.read_text()).get('root') if state.exists() else None
changed=0
for p in fpga.rglob('*'):
 if p.is_file() and p.suffix in ['.v','.vh','.al','.ipc','.sdc','.adc','.cwc']:
  raw=p.read_bytes();new=raw.replace(b'@PROJECT_ROOT@',fpga.as_posix().encode())
  if old:new=new.replace(old.encode(),fpga.as_posix().encode())
  if new!=raw:p.write_bytes(new);changed+=1
project=fpga/'project'
(root/'build').mkdir(exist_ok=True)
(project/'synth.tcl').write_text('cd {'+project.as_posix()+'}\nimport_device eagle_s20.db -package EG4S20BG256\nopen_project Tingjian.al -single_run\nreset_runs syn_1\nlaunch_runs syn_1\nwait_run syn_1\nputs TINGJIAN_SYNTHESIS_FINISHED\nexit\n')
(project/'physical.tcl').write_text('cd {'+(project/'Tingjian_Runs/phy_1').as_posix()+'}\nimport_device eagle_s20.db -package EG4S20BG256\nopen_project ../syn_1/Tingjian.prj -noanalyze\nimport_db ../syn_1/Tingjian_gate.db\nset_param flow thread 1\nplace\nreport_area -io_info -file Tingjian_phy.area\nroute\nset_param route fix_hold high\nfix_hold\nupdate_timing -mode final\nreport_timing_summary -file Tingjian_pr.timing\nreport_timing_exception -file Tingjian_exception.timing\nreport_area -io_info -file Tingjian_phy.area\nexport_db Tingjian_pr.db\nbitgen -bit Tingjian.bit\nputs TINGJIAN_PHYSICAL_FINISHED\nexit\n')
state.write_text(json.dumps({'root':fpga.as_posix()},indent=2))
print('Configured project. Changed path files:',changed)
