{
  atPos=index($1, "@")
  filesystempath=substr($1, 0, atPos - 1)
  snapshotname=substr($1, atPos + 1)
  snapshotdate=$2
  if ( ! filesystemArr[filesystempath] ) {
    filesystemArr[filesystempath] = snapshotname " " snapshotdate
  } else {
    if ( int(substr(filesystemArr[filesystempath], index(filesystemArr[filesystempath], " ") + 1)) < int(snapshotdate) ) {
      filesystemArr[filesystempath] = snapshotname " " snapshotdate
    }
  }
}
END {
  for ( key in filesystemArr )
    print key "@" filesystemArr[key]
}