
(() => {async function load(){try{const [m,r,p]=await Promise.all([RF853.rows("rr_system_migration_registry_v1",{order:"applied_at"}).catch(()=>[]),RF853.rows("rr_system_rulebook_v1",{order:"updated_at"}).catch(()=>[]),RF853.rows("rr_user_profiles",{limit:300}).catch(()=>[])]);
RF853.table("migrations",m,["migration_code","module_code","version_code","data_mode","migration_status","test_status","applied_at","last_verified_at"]);
RF853.table("rules",r,["rule_code","rule_scope","rule_text","is_locked","updated_at"]);
RF853.table("profiles",p,["display_name","role_code","department_code","access_status","is_active","auth_user_id"]);RF853.msg("msg","Backend registry/access loaded.","ok")}catch(e){RF853.msg("msg",e.message,"error")}}
refresh.onclick=load;load()})();
