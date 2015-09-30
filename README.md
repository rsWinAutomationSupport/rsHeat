rsHeat
======

```PoSh
rsHeat Environment
{
  Name = "HeatTemplate"
  Region = "IAD"
  TemplateFile = $($d.wD,$d.mR,"Test.yml" -join'\')
  TemplateHash = $($d.wD,"Test.yml.hash" -join'\')
  Parameters = @{"branch_rsConfigs"= "master";"rs_DDI"=$($d.DDI);"rs_username"=$($d.cU);"rs_apikey"=$($d.cAPI);"git_username"=$($d.gCA);"git_Oathtoken"=$($d.gAPI);}
  TimeoutMins = 60
  Ensure = "Present"
}
```