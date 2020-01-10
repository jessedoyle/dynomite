class Dynomite::Migration
  class Runner
    include Dynomite::Item::WaiterMethods

    def initialize(options={})
      @options = options
    end

    def run
      puts "Running Dynomite migrations"
      Dynomite::SchemaMigration.ensure_table_exists!

      Dynomite::Migration::FileInfo.all_files.each do |path|
        migrate(path)
      end
    end

    def migrate(path)
      load path
      file_info = FileInfo.new(path)

      migration = find_migration(file_info)
      if migration
        if migration.status == "complete"
          return
        else
          action = uncompleted_migration_prompt(file_info, migration)
        end
      end

      case action
      when :skip
        return
      when :completed
        migration.status = "completed"
        migration.save
        return
      when :exit
        puts "Exiting"
        exit
      end

      # INSERT scheme_migrations table - in_progress
      unless migration
        migration = Dynomite::SchemaMigration.new(version: file_info.version, status: "in_progress", path: file_info.path)
        migration.save
      end
      start_time = Time.now

      migration_class = file_info.migration_class
      migration_class.new.up # wait happens within create_table or update_table

      # UPDATE scheme_migrations table - complete
      migration.status = "complete"
      migration.time_took = (Time.now - start_time).to_i
      migration.save
    end

    def uncompleted_migration_prompt(file_info, migration)
      choice = nil
      until %w[s c e].include?(choice)
        puts(<<~EOL)
          The {file_info.path} migration is status is not complete. Status: #{migration.status}
          This can happen and was if the migration interupted by a CTRL-C.
          Please check the migration to figure out what to do next.

          Options:

              s - skip and continue, will leave schema_migrations item as-is
              c - mark as completed and continue, will update the schema_migrations item and mark completed.
              e - exit

          Choose an option (s/c/e):
        EOL
        choice = $stdin.gets.strip
      end

      map = {
        "s" => :skip,
        "c" => :completed,
        "e" => :exit,
      }
      map[choice]
    end

    def find_migration(file_info)
      Dynomite::SchemaMigration.find_by(version: file_info.version)
    end
  end
end
