require 'bencode'
require 'sqlite3'
require 'sequel'

# make sure there is at least 1 argument, and all arguments are directories
if ARGV.empty? || !ARGV[0] || ARGV[0].length == 0
  STDERR.puts "ERROR:  Usage:  $0 <1 or more paths to search for torrents>"
  exit(1)
else # parse the paths to ensure they all exist:
  ARGV.each do |a|
    if !File.directory?(a)
      STDERR.puts "ERROR:  Usage:  $0 <1 or more paths to search for torrents>"
      exit(1)
    end
  end
end

DB = Sequel.connect('sqlite://tf.db')

if !DB.table_exists?(:torrents)
  DB.create_table :torrents do
    primary_key :id
    String :file, size:1024, index: {unique: true}
    String :name, size:1024
    Fixnum :length
  end
end

if !DB.table_exists?(:torrent_files)
  DB.create_table :torrent_files do
    primary_key :id
    foreign_key :torrent_id, :torrents
    String :path, size:1024
    Fixnum :length
    index [:torrent_id, :path], unique:true
  end
end

class Torrent < Sequel::Model(DB[:torrents])
  set_primary_key :id
end

class TorrentFile < Sequel::Model(DB[:torrent_files])
  set_primary_key :id
end


ARGV.each do |a|
  Dir["#{a}/**/*.torrent"].each do |file|
    file = File.expand_path(file)
    puts file

    b = BEncode.load(File.read(file))
    t = Torrent.where(file: file).first 
    t = Torrent.new if t.nil?
    t.file = file
    t.name = b['info']['name']
    t.length = b['info']['length']
    t.save

    (b['info']['files'] || []).each do |f|
      tf = TorrentFile.where(:torrent_id => t.id).where(:path => f['path'].join('/')).first
      tf = TorrentFile.new if tf.nil?
      tf.torrent_id = t.id
      tf.path = f['path'].join('/')
      tf.length = f['length']
      tf.save
    end
  end
end