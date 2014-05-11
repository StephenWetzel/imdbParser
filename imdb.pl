#!/usr/bin/perl
#IMDB Parser by Dale Swanson May 20 2013
#Grabs imdb ratings and generate graphs
#requires lynx and gnuplot
#http://www.imdb.com/title/tt0092455/eprate

use strict;
use warnings;
use autodie;

#$|++; #autoflush disk buffer

my $time = time;

my $testing = 0; #set to 1 to prevent actual downloading, 0 normally
my $miny = ""; #The minimum y value in graphs, set to = "" for auto
my $imdbid = ""; #set this = "" and it will take the id from the command line
my $allavg = 7.4; #median score for all tv shows
if (!$imdbid) {$imdbid = $ARGV[0];} #grab id from command line if passed
my $title = "$imdbid"; #only used in directory name, then replaced with title from page

my $dir = "$title.$time/";
mkdir $dir;
my $plotdir=""; #directory the plots will go to, set to ="" for all in main directory
my $inputfile = "input.txt";
my $allfile = $dir."all.".$time.".csv";
my $bestworstfile = $dir."bestworst.".$time.".csv";
my $seasonavgfile = $dir."Savg.".$time.".csv";
my $gnuplotfile = $dir."plot.gp";
my $linxdump = $dir."dump.txt";
my $bestep = $dir."best.txt";
my $worstep = $dir."worst.txt";

my $url = "http://www.imdb.com/title/".$imdbid."/eprate";

my @filearray; #stores lines of input files
my $fileline; #store individual lines of input file in for loops
my $temp;
my @stats;# [x][y], x:index, y: 0:season, 1:ep, 2:title, 3:rating, 4:# ratings
my $numep=0;
my @numepseason; #number of episodes in each season
my @seasonavg; #average rating of each season
my @seasonbw; #number of the best and worst episodes in each season
my $numseasons=0; #number of seasons
my $quarter; #how many episodes make up 25% of the total number
my $parseflag=0; #what stage of parsing we are in: 0:not begun, 1:parsing, 2:done

#lynx -dump -width=9999 -nolist "http://www.imdb.com/title/tt0106145/eprate" >dump.txt
$temp = "lynx -dump -width=9999 -nolist \"$url\" > $linxdump";
#print "\n$temp\n";
if (!$testing) {system($temp);} #download page when not testing
if ($testing) {$linxdump = "dump.txt";} #if testing use saved page

open my $ifile, '<', $linxdump;
@filearray = <$ifile>;
close $ifile;
foreach $fileline (@filearray)
{#go through the linx dump, gather data
	#   IMDb > "Star Trek: The Next Generation" (1987)
	if ($fileline =~ m/\s+IMDb\s\>\s\"(.+?)\"\s+/)
	{#this line should contain title
		$title = $1;
		print "\nTitle:'$title'";
	}
	
	if ($parseflag == 0)
	{#parsing hasn't begun, look for starting line
		#     #       Episode       User
		if ($fileline =~ m/\s+\#\s+Episode\s+User/)
		{#line at begining of ratings list
			$parseflag=1;
		}
	}	
	elsif ($parseflag == 1)
	{#parsing has begun
		#   5.18  Cause and Effect    8.7   750
		if ($fileline =~ m/\s+(\d+)\.(\d+)\s+(.+?)\s+(\d+\.\d+)\s+(\d+,?\d*)\n/) #this is madness
		{#this is a line with a rating, grab the juicy data
			#print "\nEpisode Found '$1' '$2' '$3' '$4' '$5'";
			$numep++;
			$stats[$numep][0] = sprintf( "%02d", $1); #Season
			$stats[$numep][1] = sprintf( "%02d", $2); #Episode
			$stats[$numep][2] = $3; #Title
			$stats[$numep][3] = $4; #Rating
			$stats[$numep][4] = $5; #Num Raters
			$stats[$numep][4] =~ s/\D//; #strip commas
			
			# [x][y], x:index, y: 0:season, 1:ep, 2:title, 3:rating, 4:# ratings
			$numepseason[$stats[$numep][0]]++; #count episode in season
			$seasonavg[$stats[$numep][0]] += $stats[$numep][3]; #add up rating
			if ($stats[$numep][0] > $numseasons) {$numseasons = $stats[$numep][0];}		
		}
		elsif ($fileline =~ m/__________/)
		{#end of ratings, huge line of underscores
			$parseflag = 2; #2 = we're done
		}
	}
}
print "\n$numep Episodes found";


### Per episode ratings ###
$quarter = int($numep * 0.25);
open my $ofile, '>', $allfile;
open my $bfile, '>', $bestep;
open my $wfile, '>', $worstep;
print $bfile "S0E00\t;Rating\t;Num Ratings\t;Title";
print $wfile "S0E00\t;Rating\t;Num Ratings\t;Title";
for (my $i=1; $i <= $numep; $i++)
{#go through each episode
	#s + (e-1)/#s
	$temp = $stats[$i][0] + (($stats[$i][1]-1)/$numepseason[$stats[$i][0]]);
	#should be a fractional episode number, where the first of season 4 is 4.0, and last is close to 4.99
	#print "\n# $temp";
	#print "\nS$stats[$i][0]E$stats[$i][1] \t$stats[$i][3] - \t$stats[$i][4] - \t$stats[$i][2]";
	print $ofile "$temp \t$stats[$i][3]\n";
	if ($i <= $quarter)
	{#best quarter
		$seasonbw[$stats[$i][0]][0]++;
		print $bfile "\nS$stats[$i][0]E$stats[$i][1]\t;$stats[$i][3]\t;$stats[$i][4]\t;$stats[$i][2]";
	}
	
	if ($i >= $numep-$quarter)
	{#worst quarter
		$seasonbw[$stats[$i][0]][1]++;
		print $wfile "\nS$stats[$i][0]E$stats[$i][1]\t;$stats[$i][3]\t;$stats[$i][4]\t;$stats[$i][2]";
	}
}
close $ofile;
close $bfile;
close $wfile;

open  my $gfile, '>', $gnuplotfile;
print $gfile <<ENDTEXT;
set terminal png size 1200, 800 enhanced
set font "arial"
set output "$plotdir$title.all.episodes.png"
set grid
set title "$title: All Episode Ratings"
set nokey
set yrange [$miny:]
set xrange [:]
set ylabel 'Rating out of 10'
set xlabel "Season"
f(x) = a*x + b
fit f(x) "$allfile" u 1:2 via a, b
plot "$allfile" using 1:2 title "Rating" pt 2, f(x), $allavg title ""
ENDTEXT
close $gfile;
system("gnuplot $gnuplotfile 2>fit.log");


### Per season averages ###
open $ofile, '>', $seasonavgfile;
open my $bwfile, '>', $bestworstfile;
for (my $i=1; $i <= $numseasons; $i++)
{# go through each season
	$seasonavg[$i] /= $numepseason[$i];
	#if there were 0 episodes they will be undefined and mess up the output:
	if (!defined $seasonbw[$i][0]) {$seasonbw[$i][0]=0;}
	if (!defined $seasonbw[$i][1]) {$seasonbw[$i][1]=0;}
	print $ofile "$i \t$seasonavg[$i]\n";
	print $bwfile "$i \t$seasonbw[$i][0] \t$seasonbw[$i][1]\n";
	
}
close $ofile;
close $bwfile;

open  $gfile, '>', $gnuplotfile;
print $gfile <<ENDTEXT;
set terminal png size 1200, 800 enhanced
set font "arial"
set output "$plotdir$title.avg.seasons.png"
set grid
set title "$title: Average Season Ratings"
set nokey
set yrange [$miny:]
set xrange [:]
set ylabel 'Rating out of 10'
set xlabel "Season"
set boxwidth 0.5
set style fill solid
plot "$seasonavgfile" using 2: xtic(1) with boxes lc rgb "#0000ff"
ENDTEXT
close $gfile;
system("gnuplot", $gnuplotfile);

open  $gfile, '>', $gnuplotfile;
print $gfile <<ENDTEXT;
set terminal png size 1200, 800 enhanced
set font "arial"
set output "$plotdir$title.bw.seasons.png"
set grid
set title "$title: Number of Best or Worst Episodes in Each Season"
set key top left Left width 3 height 0.5 spacing 1.5 reverse box
set yrange [0:]
set xrange [:]
set ylabel 'Number of Episodes'
set xlabel "Season"
set style data histogram
set style histogram cluster gap 1
set style fill solid border -1
set boxwidth 0.9
plot "$bestworstfile" using 3:xtic(1) ti "Worst", '' u 2 ti "Best"
ENDTEXT
close $gfile;
system("gnuplot", $gnuplotfile);


print "\nDone\n\n";
