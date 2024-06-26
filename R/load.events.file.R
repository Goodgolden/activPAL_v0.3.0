load.step.times <-
  function(file_name,folder = ""){
    events_file <- load.events.file(folder,file_name)
    step_times <- as.POSIXct(events_file[which(events_file[,4]==2),1]*86400,origin="1899-12-30",tz="UTC")
    return(step_times)
  }

#' Title pre.process.events.file
#'
#' @param file_name
#' @param folder
#' @param minimum_valid_wear
#'
#' @return
#' @export
#'
#' @examples
pre.process.events.file <-
  function(file_name,folder = "", minimum_valid_wear = 20){
    events_file <- load.events.file(folder,file_name)
    events_file <- activpal.file.process(events_file, wear.time.minimum = minimum_valid_wear * 3600)
    return(events_file)
  }

#' Title load.events.file
#'
#' @param folder
#' @param file_name
#'
#' @return
load.events.file <- function(folder,file_name){
    # Load cell A1 to test if the events file contains a header
    events_file <- read.csv(paste(folder,file_name,sep=""), nrows=1, header = FALSE)
    if(events_file[1,1] == "**header**"){
      events_file <- read.csv(paste(folder,file_name,sep=""), header = FALSE)
      data_start <- grep("**data**",events_file$V1,fixed=TRUE)
      if(length(data_start) == 0){
        return(NULL)
      }
      events_file <- read.csv(paste(folder,file_name,sep=""), skip = data_start[1]+1)
    }else {
      events_file <- read.csv(paste(folder,file_name,sep=""))
    }
    # Loads an activPAL events file and processes the file
    if(colnames(events_file)[1] == "row.names"){
      events_file <- events_file[,-c(1)]
    }
    if(ncol(events_file) == 1){
      # Is not a csv file.  Load the file to see if it is semi-colon delimited
      if(events_file[1,1] == "**header**"){
        events_file <- read.csv(paste(folder,file_name,sep=""), header = FALSE)
        data_start <- grep("**data**",events_file$V1,fixed=TRUE)
        if(length(data_start) == 0){
          return(NULL)
        }
        events_file <- read.csv(paste(folder,file_name,sep=""), sep=";", skip = data_start[1]+1)
      }else {
        events_file <- read.csv(paste(folder,file_name,sep=""), sep=";", skip=1)
      }
      if(ncol(events_file) == 1){
        return(NULL)
      }
    }
    events_file <- activpal.convert.events.extended.file(events_file)

    return(events_file)
  }

#' Title activpal.file.process
#'
#' @param data
#' @param valid.days
#' @param wear.time.minimum
#'
#' @return
activpal.file.process <- function(data, valid.days = NULL,wear.time.minimum = 72000){
    # takes in an unprocessed activpal file, formatting and processing the file to allow further analysis
    # data = an unprocessed activpal event file
    # wear.time.minimum = minimum wear time required for a day to be considered valid
    process.data<-data
    if(ncol(process.data)==6){
      process.data$abs.sum <- 0
    }
    process.data<-activpal.file.process.rename.row(process.data)

    process.data$time <- as.POSIXct(process.data$time*86400,origin="1899-12-30",tz="UTC")
    process.data<-process.data[,1:7]
    process.data<-process.data[which(process.data$interval>0),]

    process.data<-activpal.file.process.merge.stepping(process.data)
    #process.data$steps<-0
    if(!is.null(valid.days)){
      process.data<-activpal.file.process.split.day(process.data,c(6,7,8))
      process.data <- process.data[which(as.Date(process.data$time) %in% valid.days),]
    }else{
      process.data <- process.data[which(process.data$interval<72000),]
      process.data<-activpal.file.process.split.day(process.data,c(6,7,8))
      process.data<-activpal.file.process.exclude.days(process.data,(86400-wear.time.minimum))
    }
    return(process.data)
  }




#' Title activpal.convert.events.extended.file
#'
#' @param data
#'
#' @return
activpal.convert.events.extended.file <- function(data){
    if(length(which(colnames(data) == "Time.approx.")) >= 1){
      if(rownames(data)[1] != 1){
        data$time <- as.numeric(rownames(data))
        data <- data[,c(ncol(data),2,4,3,6:10)]
      }else{
        data <- data[,c(1,3,5,4,7:11)]
      }
      rownames(data) <- 1:nrow(data)
      return(data)
    }else{
      return(data)
    }
  }


#' Title activpal.file.process.rename.row
#'
#' @param data
#'
#' @return
#' @export
#'
#' @examples
activpal.file.process.rename.row <- function(data){
    # Renames the initial row names of an imported activpal event file to facilitate easier processing
    # data = an unprocessed activpal event file
    process.data<-data
    # for data for no absolute sum of difference values
    if (ncol(process.data)==6){
      process.data$temp_1 <- 1
      process.data$temp_2 <- 1
      process.data$temp_3 <- 1
    }
    colnames(process.data)<-c("time","samples","interval","activity","cumulative_steps","MET.h",
                              "abs.sum.x","abs.sum.y","abs.sum.z")

    return(process.data)
  }

activpal.file.process.merge.stepping<-
  function(data){
    # Merges adjacent stepping events in an activpal event file that has been processed by activpal.file.process.rename.row
    # Adds an additional column called steps which records the total number of steps in each stepping bout
    # data - an activpal event file with standardised column names
    process.data<-data

    # Amend the number of steps to contain the correct number of steps
    # (One step in cumulative steps is equivalent to two actual steps)
    process.data$cumulative_steps<-process.data$cumulative_steps*2
    process.data$steps<-0

    # create offset lists of activity codes to allow adjacent activities to be measured
    one<-c(-1,process.data$activity)
    two<-c(process.data$activity,-1)

    # Calculate rows where stepping bouts commence
    stepping.bout.start<-which(one!=2 & two==2)
    # Calculate rows where stepping bout ends
    stepping.bout.end<-which(one==2 & two!=2)-1

    stepping.bouts<-length(stepping.bout.start)

    # Build rows for each of the each of the combined stepping bouts
    stepping.bout.start.time<-process.data[stepping.bout.start,1]
    stepping.bout.samples<-process.data[stepping.bout.start,2]
    stepping.bout.activity<-2
    stepping.bout.cumulative.steps<-process.data[stepping.bout.end,5]
    stepping.bout.steps<-process.data[stepping.bout.end,5]-process.data[(stepping.bout.start-1),5]

    stepping.bout.interval<-vector(length=stepping.bouts)
    stepping.bout.met.h<-vector(length=stepping.bouts)
    stepping.bout.abs.sum.diff<-vector(length=stepping.bouts)

    stepping.interval<-process.data[,3]
    stepping.met.h<-process.data[,6]
    stepping.abs.sum.diff<-process.data[,7]
    for(i in 1:stepping.bouts){
      stepping.bout.interval[i]<-sum(stepping.interval[(stepping.bout.start[i]:stepping.bout.end[i])])
      stepping.bout.met.h[i]<-sum(stepping.met.h[(stepping.bout.start[i]:stepping.bout.end[i])])
      stepping.bout.abs.sum.diff[i]<-sum(stepping.abs.sum.diff[(stepping.bout.start[i]:stepping.bout.end[i])])
    }

    # Combine the rows into a dataframe and renames the columns to match the main dataframe.
    stepping.bout.insert<-data.frame(stepping.bout.start.time,stepping.bout.samples,stepping.bout.interval,
                                     stepping.bout.activity,stepping.bout.cumulative.steps,stepping.bout.met.h,
                                     stepping.bout.abs.sum.diff, stepping.bout.steps)

    colnames(stepping.bout.insert)<-colnames(process.data)

    # remove the current single stepping event from the main file and replace them with the merged stepping bouts
    process.data<-process.data[which(process.data$activity!=2),]
    process.data<-rbind(process.data,stepping.bout.insert)

    # sort the dataframe by date and renumber the rows to reflect this.
    process.data<-process.data[order(process.data$time),]
    rownames(process.data)<-(1:nrow(process.data))

    return(process.data)
  }

activpal.file.process.split.day<-
  function(data,column.split=NULL){
    # Splits any events that occurs over multiple days so that each event is only within a single day
    # data = The processed activpal file that is being processed
    # col.split - a vector containing the column number of additional rows that should be split based on the duration
    process.data<-data

    prev.size<-nrow(process.data)
    process.data<-activpal.file.process.split.day.run(process.data,column.split)
    curr.size<-nrow(process.data)

    while (prev.size!=curr.size){
      # Continues to call stepping.split.day.run until no more rows are added
      # (all multi-day spanning events have been successfully split)
      process.data<-activpal.file.process.split.day.run(process.data,column.split)
      prev.size<-curr.size
      curr.size<-nrow(process.data)
    }
    return(process.data)
  }

activpal.file.process.split.day.run<-
  function(data,col.split=NULL){
    # Splits any entries that cross two or more days
    # data - an activpal data file.  The event datetime must be in column 1 and the duration of the event should be in column 2
    # col.split - a vector containing the column number of additional rows that should be split based on the duration
    transform.data<-data
    rownames(transform.data)<-1:nrow(transform.data)
    input.data.time<-transform.data$time
    input.data.interval<-transform.data[,3]
    split.col<-col.split

    one<-input.data.time
    two<-input.data.time+input.data.interval

    one<-format(one, format = "%d")
    two<-format(two, format = "%d")
    # Find the indexes where there is a transition between consecutive entries
    day.split <- c(one!= two)
    day.split.inds <- which(one!=two)

    # for each of the records spanning two day, create two entries covering individual days
    len.split<-length(day.split.inds)

    if(len.split==0){
      # No events span multiple days. Return the unaltered dataset
      return(transform.data)
    }

    for (i in (1:len.split)){
      total.interval<-data[day.split.inds[i],3]
      temp.data.before<-data[day.split.inds[i],]
      temp.data.after<-data[day.split.inds[i],]
      temp.date.add<-as.POSIXct(temp.data.before$time,origin="1970-01-01",tz="UTC")
      # Calculate the number of seconds between the activity date and the end of the year
      start.time<-as.POSIXct(paste("1970-01-01",format(temp.data.before$time,format="%H:%M:%OS1")))
      end.time<-as.POSIXct("1970-01-02")
      temp.date.add<-as.numeric(difftime(end.time,start.time,units="secs"))
      # Update the interval period so that the interval is correctly split between the two new entries
      temp.data.before$interval<-temp.date.add-0.1
      temp.data.after$interval<-temp.data.after$interval-temp.date.add+0.1
      temp.data.after$time <- temp.data.after$time + temp.date.add
      temp.data.after$time <- temp.data.after$time - (as.numeric(temp.data.after$time) %% 86400)

      # Update the MET.h and abs.sum.diff to split the values based on the proportion of the original
      # event within the split event
      if(!is.null(split.col)){
        len.loop<-length(split.col)
        for (j in (1:len.loop)){
          temp.data.before[,col.split[j]]<-temp.data.before[,col.split[j]]*temp.data.before[,3]/total.interval
          temp.data.after[,col.split[j]]<-temp.data.after[,col.split[j]]*temp.data.after[,3]/total.interval
        }
      }
      # If a stepping bout crosses multiple days ensure that the number of steps within each day is whole number
      if((temp.data.before$steps  %% 1) != 0){
        temp.data.before$steps <- round(temp.data.before$steps,0)
        temp.data.after$steps <- round(temp.data.after$steps,0)
      }
      # Test for special case where the next interval is at exactly midnight (i.e. pre-split dataframe)
      # Do not add temp.data.after as it will have an interval of 0
      # A duplicate temp.data.before is added as the original entry will be deleted
      if(temp.data.after$interval>0.00001){
        transform.data<-rbind(transform.data,temp.data.before,temp.data.after)
      }else{
        transform.data<-rbind(transform.data,temp.data.before)
      }

    }
    # Exclude the original activity frames that span multiple days
    transform.data<-subset(transform.data,!rownames(transform.data)%in%day.split.inds)
    # Process the dataframe so that the row numbering matches the activity time
    transform.data<-transform.data[order(transform.data$time),]
    rownames(transform.data)<-1:nrow(transform.data)
    return(transform.data)
  }

activpal.file.process.exclude.days<-
  function(data,exclude.time=14400){
    # Removes days where the total time for non-valid events (either no information available or activity = 4)
    # data = the process activpal file
    # exclude.time = Threshold time for excluding days based on non-activity
    process.data<-data
    # Create a temporary date column to allow processing
    process.data$date<-format(process.data$time,format="%Y-%m-%d")
    # Calculate the minimum activity time necessary for a day to be considered valid
    min.activity.time<-86400-exclude.time
    # Remove single events that exceed the minimum activity duration (remove historic files with large lagging upright / sedentary)
    process.data<-process.data[which(process.data$interval<86400),]
    # Create a subset with only valid activity data
    valid.activity<-process.data[which(process.data$activity!=4),]
    # Calculate the total activity time for each day
    daily.activity.times<-data.frame(tapply(valid.activity$interval,valid.activity$date,sum))
    colnames(daily.activity.times)<-c("active.time")
    # Select only those days with the pre-requisite level of activity
    daily.activity.times<-subset(daily.activity.times,daily.activity.times$active.time>min.activity.time)
    process.data<-subset(process.data,process.data$date %in% c(rownames(daily.activity.times)))
    # Remove the temporary date column
    process.data<-process.data[,-c(9)]
    return(process.data)

  }

get.device.serial <-
  function(data){
    # extracts the serial number from a file (assumes that the serial has the format APXXXXXX)
    # returns a blank string if no device serial is found within data
    serial_start <- regexpr("AP[[:digit:]]{6}",data)
    if (serial_start > -1){
      return(substr(data,serial_start,serial_start+7))
    }else{
      return ("")
    }

  }
