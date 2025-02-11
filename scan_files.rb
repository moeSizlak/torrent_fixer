require 'sqlite3'
require 'sequel'

# make sure there is at least 1 argument, and all arguments are directories
if ARGV.empty? || !ARGV[0] || ARGV[0].length == 0
  STDERR.puts "ERROR:  Usage: #{$0} <1 or more paths to search for data files>"
  exit(1)
else # parse the paths to ensure they are directories:
  ARGV.each do |a|
    if !File.directory?(a)
      STDERR.puts "ERROR:  Usage:  $0 <1 or more paths to search for data files>"
      exit(1)
    end
  end
end

DB = Sequel.connect('sqlite://tf.db')

# sql table for data files (disk files)
# just a list of every file and folder in the user-entered directories
# (torrent contents will be matched to disk contents in these folders)
if !DB.table_exists?(:data_files)
  DB.create_table :data_files do
    primary_key :id
    String :full_path, size:1024, index: {unique: true}
    String :name, size:1024, index: {unique: false}
    Fixnum :length
  end
end

# Sequel model
class DataFile < Sequel::Model(DB[:data_files])
  set_primary_key :id
end


ARGV.each do |a|
  Dir["#{a}/**/*"].each do |file|
    file = File.expand_path(file)
    puts file

    f = DataFile.where(full_path: file).first 
    f = DataFile.new if f.nil?
    f.full_path = file
    f.name = File.basename(file)
    if !File.directory?(file)
      begin
        f.length = File.stat(file).size
      rescue Exception => e
        f = nil
        puts "      ERROR: Skipping #{file} due to #{e.message}"
        next
      end
    end
    f.save
  end
end