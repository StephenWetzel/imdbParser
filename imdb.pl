#!/usr/bin/perl
#IMDB Parser by Stephen Wetzel May 20 2013
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
my $imdbId = ""; #set this = "" and it will take the id from the command line
my $allAvg = 7.4; #median score for all tv shows
my $plotWidth = 1200; #size in pixels of the plots
my $plotHeight = 800;

if (!$imdbId) {$imdbId = $ARGV[0];} #grab id from command line if passed
my $title = "$imdbId"; #only used in directory name, then replaced with title from page

my $dir = "$title.$time/";
mkdir $dir; #a directory for the data files
my $plotDir=""; #directory the plots will go to, set to ="" for all in main directory
#my $inputFile = "input.txt";
my $allEpisodesFile = $dir."all.".$time.".csv";
my $bestWorstFile = $dir."bestworst.".$time.".csv";
my $seasonAvgFile = $dir."Savg.".$time.".csv";
my $gnuPlotFile = $dir."plot.gp";
my $linxDump = $dir."dump.txt";
my $bestEpisodesFile = $dir."best.txt";
my $worstEpisodesFile = $dir."worst.txt";

my $url = "http://www.imdb.com/title/".$imdbId."/eprate";

my @fileArray; #stores lines of input files
my $thisLine; #store individual lines of input file in for loops
my $temp;
my @stats;# [x][y], x:index, y: 0:season, 1:ep, 2:title, 3:rating, 4:# ratings
my $numEpisodes=0;
my @numEpisodesInSeason; #number of episodes in each season
my @seasonAvg; #average rating of each season
my @seasonBestWorst; #number of the best and worst episodes in each season
my $numSeasons=0; #number of seasons
my $quarter; #how many episodes make up 25% of the total number
my $parseFlag=0; #what stage of parsing we are in: 0:not begun, 1:parsing, 2:done

#lynx -dump -width=9999 -nolist "http://www.imdb.com/title/tt0106145/eprate" >dump.txt
$temp = "lynx -dump -width=9999 -nolist \"$url\" > $linxDump";
if (!$testing) {system($temp);} #download page when not testing
if ($testing) {$linxDump = "dump.txt";} #if testing use saved page

open my $ifile, '<', $linxDump;
@fileArray = <$ifile>;
close $ifile;
foreach $thisLine (@fileArray)
{#go through the linx dump, gather data
	#   IMDb > "Star Trek: The Next Generation" (1987)
	if ($thisLine =~ m/\s+IMDb\s\>\s\"(.+?)\"\s+/)
	{#this line should contain title
		$title = $1;
		print "\nTitle:'$title'";
	}
	
	if ($parseFlag == 0)
	{#parsing hasn't begun, look for starting line
		#     #       Episode       User
		if ($thisLine =~ m/\s+\#\s+Episode\s+User/)
		{#line at begining of ratings list
			$parseFlag=1;
		}
	}	
	elsif ($parseFlag == 1)
	{#parsing has begun
		#   5.18  Cause and Effect    8.7   750
		if ($thisLine =~ m/\s+(\d+)\.(\d+)\s+(.+?)\s+(\d+\.\d+)\s+(\d+,?\d*)\n/) #this is madness
		{#this is a line with a rating, grab the juicy data
			#print "\nEpisode Found '$1' '$2' '$3' '$4' '$5'";
			$numEpisodes++;
			$stats[$numEpisodes][0] = sprintf( "%02d", $1); #Season
			$stats[$numEpisodes][1] = sprintf( "%02d", $2); #Episode
			$stats[$numEpisodes][2] = $3; #Title
			$stats[$numEpisodes][3] = $4; #Rating
			$stats[$numEpisodes][4] = $5; #Num Raters
			$stats[$numEpisodes][4] =~ s/\D//; #strip commas
			
			# [x][y], x:index, y: 0:season, 1:ep, 2:title, 3:rating, 4:# ratings
			$numEpisodesInSeason[$stats[$numEpisodes][0]]++; #count episode in season
			$seasonAvg[$stats[$numEpisodes][0]] += $stats[$numEpisodes][3]; #add up rating
			if ($stats[$numEpisodes][0] > $numSeasons) {$numSeasons = $stats[$numEpisodes][0];}		
		}
		elsif ($thisLine =~ m/__________/)
		{#end of ratings, huge line of underscores
			$parseFlag = 2; #2 = we're done
		}
	}
}
print "\n$numEpisodes Episodes found";


### Per episode ratings ###
#dump formatted episode data to various text files
$quarter = int($numEpisodes * 0.25);
open my $ofile, '>', $allEpisodesFile;
open my $bfile, '>', $bestEpisodesFile;
open my $wfile, '>', $worstEpisodesFile;
print $bfile "S0E00\t;Rating\t;Num Ratings\t;Title";
print $wfile "S0E00\t;Rating\t;Num Ratings\t;Title";
for (my $i=1; $i <= $numEpisodes; $i++)
{#go through each episode
	# seasons + (episode-1) / numEpisodesSeason
	$temp = $stats[$i][0] + (($stats[$i][1]-1)/$numEpisodesInSeason[$stats[$i][0]]);
	#should be a fractional episode number, where the first of season 4 is 4.0, and last is close to 4.99
	print $ofile "$temp \t$stats[$i][3]\n";
	if ($i <= $quarter)
	{#best quarter
		$seasonBestWorst[$stats[$i][0]][0]++;
		print $bfile "\nS$stats[$i][0]E$stats[$i][1]\t;$stats[$i][3]\t;$stats[$i][4]\t;$stats[$i][2]";
	}
	
	if ($i >= $numEpisodes-$quarter)
	{#worst quarter
		$seasonBestWorst[$stats[$i][0]][1]++;
		print $wfile "\nS$stats[$i][0]E$stats[$i][1]\t;$stats[$i][3]\t;$stats[$i][4]\t;$stats[$i][2]";
	}
}
close $ofile;
close $bfile;
close $wfile;

#create a gnuPlot script to handle plotting
open  my $gfile, '>', $gnuPlotFile;
print $gfile <<ENDTEXT;
set terminal png size $plotWidth, $plotHeight enhanced
set font "arial"
set output "$plotDir$title.all.episodes.png"
set grid
set title "$title: All Episode Ratings"
set nokey
set yrange [$miny:]
set xrange [:]
set ylabel 'Rating out of 10'
set xlabel "Season"
f(x) = a*x + b
fit f(x) "$allEpisodesFile" u 1:2 via a, b
plot "$allEpisodesFile" using 1:2 title "Rating" pt 2, f(x), $allAvg title ""
ENDTEXT
close $gfile;
system("gnuplot $gnuPlotFile 2>fit.log");


### Per season averages ###
open $ofile, '>', $seasonAvgFile;
open my $bwfile, '>', $bestWorstFile;
for (my $i=1; $i <= $numSeasons; $i++)
{# go through each season
	$seasonAvg[$i] /= $numEpisodesInSeason[$i];
	#if there were 0 episodes they will be undefined and mess up the output:
	if (!defined $seasonBestWorst[$i][0]) {$seasonBestWorst[$i][0]=0;}
	if (!defined $seasonBestWorst[$i][1]) {$seasonBestWorst[$i][1]=0;}
	print $ofile "$i \t$seasonAvg[$i]\n";
	print $bwfile "$i \t$seasonBestWorst[$i][0] \t$seasonBestWorst[$i][1]\n";
}
close $ofile;
close $bwfile;

open  $gfile, '>', $gnuPlotFile;
print $gfile <<ENDTEXT;
set terminal png size $plotWidth, $plotHeight enhanced
set font "arial"
set output "$plotDir$title.avg.seasons.png"
set grid
set title "$title: Average Season Ratings"
set nokey
set yrange [$miny:]
set xrange [:]
set ylabel 'Rating out of 10'
set xlabel "Season"
set boxwidth 0.5
set style fill solid
plot "$seasonAvgFile" using 2: xtic(1) with boxes lc rgb "#0000ff"
ENDTEXT
close $gfile;
system("gnuplot", $gnuPlotFile);

open  $gfile, '>', $gnuPlotFile;
print $gfile <<ENDTEXT;
set terminal png size $plotWidth, $plotHeight enhanced
set font "arial"
set output "$plotDir$title.bw.seasons.png"
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
plot "$bestWorstFile" using 3:xtic(1) ti "Worst", '' u 2 ti "Best"
ENDTEXT
close $gfile;
system("gnuplot", $gnuPlotFile);


print "\nDone\n\n";
