If you ever lose your QBT data due to a hard disk loss (or other reasons), this tool will allow you to re-add all your torrent files to QBT.  The requirements are:
* You need to have all of the torrent files (redownload them from their original source).  Some trackers allow you to mass-download all of the torrents you have ever leached.
* You need to have the data files.  This tool will search for them and find them where ever they may be, and add them to QBT with the correct path, and also skip the hash-recheck.  (The files must have the correct name and file size.)

Usage:
* ruby scan_torrents.rb \<list of directories to search for *.torrent files\>
* ruby scan_files.rb \<list of directories to search for data files\>
* ruby send_qbt.rb \<URL of QBittorrent API such as http://localhost:8080 \> \<username\> \<password\>

