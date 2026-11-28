# Installed alongside the root-owned deployment helper; executed as runtime, read-only.
require "json"
require "digest"
result = { databases: {}, pending: [] }
ActiveRecord::Base.configurations.configs_for(env_name: "production").each do |config|
  ActiveRecord::Base.establish_connection(config)
  connection = ActiveRecord::Base.connection
  connection.transaction do
    connection.execute("SET TRANSACTION READ ONLY")
    raise "Uninitialized database" unless connection.table_exists?("schema_migrations")
    raise "Runtime schema privilege" if connection.select_value("SELECT has_schema_privilege(current_user,'public','CREATE')")
    role = connection.select_one("SELECT rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user")
    raise "Elevated runtime role" if role.values.any?
    tables = connection.tables.sort
    invalid_indexes = connection.select_values("SELECT indexrelid::regclass::text FROM pg_index JOIN pg_class ON pg_class.oid=indrelid WHERE relnamespace='public'::regnamespace AND (NOT indisvalid OR NOT indisready)")
    invalid_constraints = connection.select_values("SELECT conname FROM pg_constraint WHERE connamespace='public'::regnamespace AND NOT convalidated")
    raise "Invalid database objects" if invalid_indexes.any? || invalid_constraints.any?
    tables.each do |table|
      %w[SELECT INSERT UPDATE DELETE].each do |privilege|
        raise "Missing runtime privilege" unless connection.select_value("SELECT has_table_privilege(current_user,#{connection.quote(connection.quote_table_name(table))},#{connection.quote(privilege)})")
      end
    end
    if config.name == "primary"
      roles = connection.select_all("SELECT rolname,rolsuper,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname IN ('muzeum_runtime','muzeum_migrator')").to_a
      raise "Restricted migration/runtime roles required" unless roles.size == 2 && roles.none? { |role| role.values_at("rolsuper", "rolcreatedb", "rolcreaterole").any? }
      raise "Runtime ownership membership" if connection.select_value("SELECT pg_has_role(current_user,'muzeum_owner','MEMBER') OR pg_has_role(current_user,'muzeum_migrator','MEMBER')")
    end
    if config.name == "queue" && ENV["MUZEUM_DEPLOY_CHECK_HEALTH"] == "1"
      [ "Supervisor(#{SolidQueue::Configuration.new.mode})", "Dispatcher", "Worker", "Scheduler" ].each do |kind|
        alive = connection.select_value("SELECT EXISTS(SELECT 1 FROM solid_queue_processes WHERE kind=#{connection.quote(kind)} AND last_heartbeat_at > #{connection.quote(SolidQueue.process_alive_threshold.ago)})")
        raise "Solid Queue process heartbeat unavailable" unless alive
      end
    end
    paths = Array(config.configuration_hash[:migrations_paths] || "db/migrate")
    versions = connection.select_values("SELECT version FROM schema_migrations").map(&:to_s)
    migrations = paths.flat_map { |path| Dir.glob(Rails.root.join(path, "[0-9]*_*.rb")) }.sort
    files = migrations.map { |file| [ File.basename(file).split("_").first, file.delete_prefix("#{Rails.root}/") ] }
    raise "Duplicate migration version" unless files.map(&:first).uniq.size == files.size
    baseline = if config.name == "primary"
      []
    else
      schema = File.read(Rails.root.join("db", "#{config.name}_schema.rb"))
      [ schema.match(/define\(version: ([0-9_]+)\)/).captures.first.delete("_") ]
    end
    raise "Database has unknown migrations" unless (versions - files.map(&:first) - baseline).empty?
    files.reject { |version, _| versions.include?(version) }.each do |version, path|
      result[:pending] << { database: config.name, version: version, path: path, sha256: Digest::SHA256.file(Rails.root.join(path)).hexdigest }
    end
    indexes = connection.select_all(<<~SQL).to_a
      SELECT c.relname AS indexname, pg_get_indexdef(c.oid) AS indexdef, i.indisvalid, i.indisready
      FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid
      WHERE c.relnamespace = 'public'::regnamespace ORDER BY c.relname
    SQL
    columns = connection.select_all(<<~SQL).to_a
      SELECT c.relname AS table_name, a.attname AS column_name, a.attnum AS position,
             format_type(a.atttypid, a.atttypmod) AS data_type, a.attnotnull AS not_null,
             a.attidentity AS identity_kind, a.attgenerated AS generated_kind,
             a.attcollation::regcollation::text AS collation, pg_get_expr(d.adbin, c.oid) AS default_expression
      FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
      WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p')
        AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY c.relname, a.attnum
    SQL
    constraints = connection.select_all("SELECT conrelid::regclass::text AS table_name,conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE connamespace='public'::regnamespace ORDER BY conrelid::regclass::text,conname").to_a
    if config.name == "primary"
      required_indexes = %w[index_scrobbles_on_lastfm_account_id_and_source_fingerprint index_scrobbles_on_lastfm_account_id_and_played_at_and_id one_active_import_per_account due_lastfm_accounts]
      raise "Missing required source index" unless (required_indexes - indexes.map { |index| index["indexname"] }).empty?
    end
    triggers = connection.select_all("SELECT c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) AS definition,pg_get_functiondef(t.tgfoid) AS function FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE NOT t.tgisinternal AND c.relnamespace='public'::regnamespace ORDER BY c.relname,t.tgname").to_a
    raise "Disabled source protection" if triggers.any? { |trigger| trigger["tgenabled"] != "O" }
    if config.name == "primary"
      required = [ [ "scrobbles", "preserve_scrobble_source" ], [ "scrobbles", "preserve_scrobble_identifier" ], [ "import_pages", "preserve_raw_page" ] ]
      %w[scrobbles import_pages source_fetches source_deliveries ingestion_issues page_commits lastfm_account_names].each do |table|
        required << [ table, "retain_truncate_#{table}" ]
      end
      %w[source_fetches source_deliveries ingestion_issues page_commits lastfm_account_names].each do |table|
        required << [ table, "retain_#{table}" ]
      end
      raise "Missing source protection" unless (required - triggers.map { |trigger| trigger.values_at("relname", "tgname") }).empty?
    end
    result[:databases][config.name] = { database: connection.select_value("SELECT current_database()"), versions: versions.sort, tables: tables, columns: columns, triggers: triggers, indexes: indexes, constraints: constraints }
  end
end
raise "Four databases required" unless result[:databases].keys.sort == %w[cable cache primary queue]
puts "MUZEUM_DEPLOY_INSPECTION:" + JSON.generate(result)
