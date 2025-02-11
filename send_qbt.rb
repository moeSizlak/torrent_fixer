require 'sqlite3'
require 'sequel'
require 'httpx'
require 'logger'

# make sure there is at least 1 argument, and all arguments are directories
if ARGV.count != 3 || !ARGV[0] || ARGV[0][0..3] != 'http' 
  STDERR.puts "ERROR:  Usage:  $0 <URL of QBittorrent API such as http://localhost:8080> <username> <password>"
  exit(1)
end

url = ARGV[0]
username = ARGV[1]
password = ARGV[2]


response = HTTPX.post(ARGV[0] + '/api/v2/auth/login', headers: { 'Referer' => url }, form: {'username' => username, 'password' => password})

auth = response.headers.get("set-cookie").find{|x| x[0..3] = 'SID='}
#puts "Auth=#{auth}"

if !auth
  STDERR.puts "ERROR:  Could not log in to QBittorrent."
  exit(1)
end

DB = Sequel.connect('sqlite://tf.db') #, :loggers => [Logger.new($stdout)])


single_file_torrents = DB['select a.file, b.full_path
from torrents a
inner join data_files b on b.length is not null and b.name=a.name and a.length = b.length
where a.length is not null
'].all

puts "Found #{single_file_torrents.count} single-file torrents that match.  Uploading..."

single_file_torrents.each_with_index do |r, i|
  split = File.split(r[:full_path])

  # i needed to adjust the savepaths to correct for differences between the mount path and the local paths of the qbt server, this will need to be tweaked for other users:
  savepath = split[0].gsub(/\//,'\\').gsub(/^\\mnt\\thor_(.)\\/, '\1:\\')
  savepath[0] = savepath[0].upcase

  myform= {
    'torrents' => File.open(r[:file]), 
    'savepath' => savepath,
    'skip_checking' => 'true',
    'paused' => 'false'
  }

  if split[1] =~ /2160[pP]/
    myform['category'] = 'UHD'
  end

  puts "#{i}\t#{split[1]}\t#{savepath}"

  #response = HTTPX.post('http://127.0.0.1:6969/api/v2/torrents/add', headers: {'Set-cookie' => auth}, form: myform)
  response = HTTPX.post(ARGV[0] + '/api/v2/torrents/add', headers: {'Cookie' => auth}, form: myform)

  puts "------> #{response.status}" if response.status != 200
  #exit(0) if i==20
end



multi_file_torrents = DB['select a.*, aa.id as dfolderid, aa.full_path as dfolderfullpath
from torrents a
inner join data_files aa on a.name=aa.name and aa.length is null
where a.length is null
order by a.id, aa.id
'].all

puts "Found #{multi_file_torrents.count} possible multi-file torrents that match.  Checking and uploading..."

multi_file_torrents.each_with_index do |r, i|

  file_not_found = DB['select 
  count(*) as file_not_found 
  from (
    select a.*, aa.id as tfid, aa.path as tfpath, aa.length as tflength
    , b.full_path as dfilefullpath
    from torrents a
    inner join torrent_files aa on a.id=aa.torrent_id
    left join data_files b on b.length=aa.length and b.full_path = ? || \'/\' || aa.path
    where a.length is null
    and a.id = ?
   ) z
   where z.dfilefullpath is null', r[:dfolderfullpath], r[:id]].first[:file_not_found] rescue 9999

  if file_not_found == 0
    split = File.split(r[:dfolderfullpath])

    # i needed to adjust the savepaths to correct for differences between the mount path and the local paths of the qbt server, this will need to be tweaked for other users:
    savepath = split[0].gsub(/\//,'\\').gsub(/^\\mnt\\thor_(.)\\/, '\1:\\')
    savepath[0] = savepath[0].upcase

    myform= {
      'torrents' => File.open(r[:file]), 
      'savepath' => savepath,
      'skip_checking' => 'true',
      'paused' => 'false'
    }

    if split[1] =~ /2160[pP]/
      myform['category'] = 'UHD'
    end

    puts "#{i}\t#{split[1]}\t#{savepath}"

    #response = HTTPX.post('http://127.0.0.1:6969/api/v2/torrents/add', headers: {'Cookie' => auth}, form: myform)
    response = HTTPX.post(ARGV[0] + '/api/v2/torrents/add', headers: {'Cookie' => auth}, form: myform)

    puts "------> #{response.status}" if response.status != 200
    #exit(0) if i > 8
  else
    puts "#{i}\t#{r[:file]}"
    puts "------> file_not_found = #{file_not_found}"
  end
end




