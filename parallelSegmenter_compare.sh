#!/bin/sh
#parallelSegmenter - Batch clipping videos with common start and end frames
echo
echo "=========================================================================="
echo "                            parallelSegmenter                             "
echo "         Batch clipping videos with common start and end frames           "
echo "=========================================================================="
echo

findMatch () {
	local i="$1"
	local frame="temp/$i.jpg"
	local baseline="$2"
	local kind="$3"
	local metric=$(compare -metric MAE "$frame" "$baseline" null: 2>&1 | awk '{ print $1 }')
	metric=$(echo "scale=0; $metric/1" | bc)
	if [[ "$metric" -lt 1000 ]]; then 
		if [[ "$kind" == "start" ]]; then
			#Add 1 (to get frame number of Start Frame) and convert to timecode in format ss.xxx
			localStart=$(echo "scale=3; ($i + 1)/(24000/1001)" | bc)
			echo $localStart
		elif [[ "$kind" == "end" ]]; then
			#Convert to timecode in format ss.xx
			localEnd=$(echo "scale=3; ($i - 2)/(24000/1001)" | bc)
			echo $localEnd
		fi
	fi
}
export -f findMatch

#Make an output dir
if [[ ! -d output/ ]]; then
	mkdir output
fi

for movie in *.mp4; do
	echo "Starting work on $movie..."
	#Clear all variables and do some setup
	log="output/$(basename "$movie" .mp4).txt"
	totalFrames=""
	startRange=""
	endRange=""
	metric=""
	adjustedStart=""
	adjustedEnd=""
	starts=()
	ends=()
	total=""
	compCmds=""

	#Make a clean temp dir
	if [[ -d temp/ ]]; then
		rm -rf temp
		mkdir temp
	else
		mkdir temp
	fi

	# #Generate frames for comparison
	echo "Making thumbnails..."
	ffmpeg -loglevel panic -i "$movie" -q:v 2 -vf scale=400:-1 -f image2 temp/%d.jpg

	#Set a search range for the start and end points
	echo "Finding start and end frames..."
	totalFrames=$(ls -l temp/ | wc -l)
	totalFrames=$(expr $totalFrames - 1)
	startRange=$(echo "scale=0; ($totalFrames*.20)/1" | bc)
	endRange=$(echo "scale=0; ($totalFrames*.80)/1" | bc)

	#Get the latest frame that matches Start Frame - 1 (in case Start Frame is black)
	compCmds=""
	for i in $(seq 1 $startRange); do
		compCmds+="findMatch $i tests/start.jpg start\n"
	done
	starts=( $(echo $compCmds | parallel -k -u) )
	total="${#starts[@]}"
	adjustedStart="${starts[$(( $total-1 ))]}"

	#Get the latest frame that matches End Frame
	compCmds=""
	for i in $(seq $endRange $totalFrames); do 
		compCmds+="findMatch $i tests/end.jpg end\n"
	done
	ends=( $(echo $compCmds | parallel -k -u) )
	total="${#ends[@]}"
	adjustedEnd="${ends[$(( $total-1 ))]}"

	echo "     Start: $adjustedStart    End: $adjustedEnd"
	#Clip out the segment we want
	echo "Saving segmented clip..."
	ffmpeg -loglevel panic -i "$movie" -ss $adjustedStart -to $adjustedEnd -c:v libx264 -crf 16 -tune animation -level 41 -c:a copy -movflags faststart -y output/"$movie" && echo "Clip saved!"
	echo
done