require 'sqlite3'
require 'sequel'
require 'httpx'
require 'logger'

# make sure there are 3 arguments
if ARGV.count != 3 || !ARGV[0] || ARGV[0][0..3] != 'http' 
  STDERR.puts "ERROR:  Usage: #{$0} <URL of QBittorrent API such as http://localhost:8080> <username> <password>"
  exit(1)
end

url = ARGV[0]
username = ARGV[1]
password = ARGV[2]

# try to login:
response = HTTPX.post(ARGV[0] + '/api/v2/auth/login', headers: { 'Referer' => url }, form: {'username' => username, 'password' => password})

# need to get the SID cookie which needs to be sent in all subsequent API calls
auth = response.headers.get("set-cookie").find{|x| x[0..3] = 'SID='}
#puts "Auth=#{auth}"

if !auth
  STDERR.puts "ERROR:  Could not log in to QBittorrent."
  exit(1)
end

DB = Sequel.connect('sqlite://tf.db') #, :loggers => [Logger.new($stdout)])


######################################################################################################################################
# SINGLE-FILE TORRENTS
######################################################################################################################################

# search for SINGLE-FILE torrents where the single file exists on the hard drive (same file name) and is the correct size.
# (size is checked, not file checksums)
single_file_torrents = DB['select a.file, b.full_path
from torrents a
inner join data_files b on b.length is not null and b.name=a.name and a.length = b.length
where a.length is not null
'].all

puts "Found #{single_file_torrents.count} single-file torrents that match.  Uploading..."

single_file_torrents.each_with_index do |r, i|
  split = File.split(r[:full_path]) # split[0] is the disk path, and split[1] is the filename

  # this is the savepath that gets sent to QBT, so it needs to be relative to the QBT server
  # i needed to adjust the savepaths to correct for differences between the mount path on the server runnning this script 
  # and the local paths on the QBT server.
  # this will need to be tweaked for other users:

  # change /mnt/thor_k/rest/of/path to K:\rest\of\path
  savepath = split[0].gsub(/\//,'\\').gsub(/^\\mnt\\thor_(.)\\/, '\1:\\')
  savepath[0] = savepath[0].upcase

  # this is the form that will be sent to QBT when adding the torrent
  myform= {
    'torrents' => File.open(r[:file]), 
    'savepath' => savepath,
    'skip_checking' => 'true',
    'paused' => 'false'
  }

  # this is a categoy I use just for certain torrents.  you can add your own
  if split[1] =~ /2160[pP]/
    myform['category'] = 'UHD'
  end

  # log to screen
  puts "#{i}\t#{split[1]}\t#{savepath}"

  # you can run netcat (nc -l 6969 or nc -l 6969 > http_request.txt) to view how the API call will look 
  #response = HTTPX.post('http://127.0.0.1:6969/api/v2/torrents/add', headers: {'Set-cookie' => auth}, form: myform)

  # make the api call:
  response = HTTPX.post(ARGV[0] + '/api/v2/torrents/add', headers: {'Cookie' => auth}, form: myform)

  # if it was not successful, log to screen
  puts "------> #{response.status}" if response.status != 200

  # can just do the first few torrents to make sure they're working if you want
  #exit(0) if i==20
end


######################################################################################################################################
# MULTI-FILE TORRENTS
######################################################################################################################################

# search for MULTI-FILE torrents where the root folder name exists on the disk (possibly in more than 1 place)
multi_file_torrents = DB['select a.*, aa.id as dfolderid, aa.full_path as dfolderfullpath
from torrents a
inner join data_files aa on a.name=aa.name and aa.length is null
where a.length is null
order by a.id, aa.id
'].all

puts "Found #{multi_file_torrents.count} possible multi-file torrents that match.  Checking and uploading..."

# for each possible match:
multi_file_torrents.each_with_index do |r, i|

  # file_not_found will be the number of files in the torrent that do not exist in the correct path relative to the root folder of the torrent,
  # or are not the correct size:

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

  # if ALL the files of the torrent exist with the correct name, path, and size, lets send it to QBT:
  if file_not_found == 0
    split = File.split(r[:dfolderfullpath]) # split[0] is the disk path, and split[1] is the filename

    # this is the savepath that gets sent to QBT, so it needs to be relative to the QBT server
    # i needed to adjust the savepaths to correct for differences between the mount path on the server runnning this script 
    # and the local paths on the QBT server.
    # this will need to be tweaked for other users:

    # change /mnt/thor_k/rest/of/path to K:\rest\of\path
    savepath = split[0].gsub(/\//,'\\').gsub(/^\\mnt\\thor_(.)\\/, '\1:\\')
    savepath[0] = savepath[0].upcase

    # this is the form that will be sent to QBT when adding the torrent
    myform= {
      'torrents' => File.open(r[:file]), 
      'savepath' => savepath,
      'skip_checking' => 'true',
      'paused' => 'false'
    }

    # this is a categoy I use just for certain torrents.  you can add your own
    if split[1] =~ /2160[pP]/
      myform['category'] = 'UHD'
    end

    # log to screen
    puts "#{i}\t#{split[1]}\t#{savepath}"

    # you can run netcat (nc -l 6969 or nc -l 6969 > http_request.txt) to view how the API call will look 
    #response = HTTPX.post('http://127.0.0.1:6969/api/v2/torrents/add', headers: {'Cookie' => auth}, form: myform)

    # make API call:
    response = HTTPX.post(ARGV[0] + '/api/v2/torrents/add', headers: {'Cookie' => auth}, form: myform)

    # if it was not successful, log to screen
    puts "------> #{response.status}" if response.status != 200

    # can just do the first few torrents to make sure they're working if you want
    #exit(0) if i > 8

  else # one or more files of the torrent do not exist, or have the correct name, path, or size:
    puts "#{i}\t#{r[:file]}"
    puts "------> file_not_found = #{file_not_found}"
  end
end




