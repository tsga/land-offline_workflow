#!/bin/bash -le
#SBATCH --job-name=sfc_bufr2ioda
#SBATCH --account=da-cpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --tasks-per-node=2
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=4G
#SBATCH -t 00:29:00
#SBATCH -o erlog
#SBATCH -e erlog


# source: https://github.com/NOAA-EMC/rrfs-workflow/blob/2b4623addc16ea4a1201957c3181c99fc9316be6/scripts/exrrfs_ioda_bufr.sh#L166-L210

#-----------------------------------------------------------------------
#
export OBSPATH=/scratch3/NCEPDEV/stmp/Tseganeh.Gichamo/CIT/COMROOT/C192E96_hybatmsoilDA/gdas.20240601/00/obs/
export IODADIR=/scratch3/NCEPDEV/da/Tseganeh.Gichamo/ioda-bundle/build/
export PARM_IODACONV=/scratch3/NCEPDEV/da/Tseganeh.Gichamo/land-offline_workflow/HOMEgfs/parm/iodaconv/
export FIX_JEDI=/scratch3/NCEPDEV/da/Tseganeh.Gichamo/land-offline_workflow/HOMEgfs/fix/jedi/
export EXECdir=${IODADIR}

export WORKDIR=/scratch3/NCEPDEV/da/Tseganeh.Gichamo/land-offline_workflow/USH
cd $WORKDIR

module use /scratch3/NCEPDEV/da/Tseganeh.Gichamo/gwdevelop/sorc/gdas.cd/modulefiles/GDAS
module load ursa.intel
export LD_LIBRARY_PATH="${IODADIR}/lib64:${LD_LIBRARY_PATH}"

ulimit -s unlimited
ulimit -v unlimited

CDATE=2024060100
pgmout="erlog"
#
#--------------------------------------------------------------------------------------------------------
# Extract from CDATE the starting year, month, day, and hour of the
# forecast.  These are needed below for various operations.
#
#-----------------------------------------------------------------------
#
START_DATE=$(echo "${CDATE}" | sed 's/\([[:digit:]]\{2\}\)$/ \1/')
YYYYMMDDHH=$(date +%Y%m%d%H -d "${START_DATE}")
YYYYMMDDHHm1=$(date +%Y%m%d%H -d "${START_DATE} 1 hour ago")
JJJ=$(date +%j -d "${START_DATE}")

YYYY=${YYYYMMDDHH:0:4}
MM=${YYYYMMDDHH:4:2}
DD=${YYYYMMDDHH:6:2}
HH=${YYYYMMDDHH:8:2}
YYYYMMDD=${YYYYMMDDHH:0:8}

YYJJJHH=$(date +"%y%j%H" -d "${START_DATE}")
PREYYJJJHH=$(date +"%y%j%H" -d "${START_DATE} 1 hours ago")
#
#-----------------------------------------------------------------------
#
# link the executable file
#
#-----------------------------------------------------------------------
#
echo "starting bufr2ioda"

export pgm="bufr2ioda.x"

#-----------------------------------------------------------------------
#
# check the existence of the PrepBUFR file for the current cycle,
# if the file is present, convert the data into ioda format for
# aircraft, ascatw, gpsipw, mesonet, profiler, rassda,
# satwnd, surface, upperair subsets.
#
#-----------------------------------------------------------------------
#
run_process_prepbufr=false
obs_file=prepbufr
#checkfile=${OBSPATH}/${YYYYMMDDHH}.rap.t${HH}z.prepbufr.tm00
checkfile=${OBSPATH}/gdas.t${HH}z.prepbufr
if [ -r "${checkfile}" ]; then
  echo "Found ${checkfile}; Use it as observation "
  cp -p ${checkfile} ${obs_file}
  run_process_prepbufr=true
else
  echo "Warning: PrepBUFR file  ${checkfile}  for ${YYYYMMDDHH} does not exist!"
fi
#
#-----------------------------------------------------------------------
#
# Copy all bufr files to be converted to ioda format
#
#-----------------------------------------------------------------------
#
#cp "${OBSPATH}/${CDATE}.rap.t${cyc}z.satwnd.tm00.bufr_d" satwndbufr
#cp "${OBSPATH}/${CDATE}.rap.t${cyc}z.gsrcsr.tm00.bufr_d" abibufr
#cp "${OBSPATH}/${CDATE}.rap.t${cyc}z.atms.tm00.bufr_d" atmsbufr
#cp "${OBSPATH}/${CDATE}.rap.t${cyc}z.crisf4.tm00.bufr_d" crisfsbufr
#
#-----------------------------------------------------------------------
#
# Modify yaml template and run bufr2ioda (prepbufr)
#
#-----------------------------------------------------------------------

yaml_list=(
"prepbufr_adpsfc.yaml"
#"prepbufr_adpupa.yaml"  # use python
#"prepbufr_aircar.yaml"
#"prepbufr_aircft.yaml"
#"prepbufr_ascatw.yaml"
#"prepbufr_msonet.yaml"
#"prepbufr_proflr.yaml"
#"prepbufr_rassda.yaml"
"prepbufr_sfcshp.yaml"
#"prepbufr_vadwnd.yaml"
)


formatted_time=$(date -d"${YYYYMMDDHH:0:8} ${YYYYMMDDHH:8:2}" '+%Y-%m-%dT%H:%M:%SZ')

for yamlfile in "${yaml_list[@]}"; do
  
  echo "processing $yamlfile"

  message_type=$(basename "$yamlfile" .yaml | awk -F'_' '{print $NF}')

  cp -p ${PARM_IODACONV}/${yamlfile} .
  sed -i "s/@referenceTime@/${formatted_time}/" "${yamlfile}"

#  cp -p ${FIX_JEDI}/ioda_empty.nc  ioda_${message_type}.nc

  if [[ ${run_process_prepbufr} ]]; then
    time srun '--export=ALL' --label -K -n 1  ${EXECdir}/bin/$pgm ${yamlfile} >> erlog 2>errfile
    export err=$?
    if [ $err -ne 0 ]; then
      if grep -qF "No valid BUFR subsets were found" errfile; then
        echo "WARNING: ${message_type}: no valid BUFR subsets in input. Skipping this type." >> erlog
        export err=0
      fi
    fi
    err_chk
    mv errfile errfile_${message_type}
  fi
done
