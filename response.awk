NR==1,/^\r$/ {next}
{printf "%s%s",$0,RT}
