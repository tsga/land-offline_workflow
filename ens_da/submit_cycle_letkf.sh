#! /bin/sh -l
#SBATCH --job-name=land_jedi
#SBATCH --account=da-cpu
#SBATCH --qos=batch
#SBATCH --nodes=10
#SBATCH --tasks-per-node=24
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH -t 07:59:00
#SBATCH -o logen_%j
#SBATCH -e erren_%j

#export jedi_mods=/scratch2/NCEPDEV/land/data/jedi/fv3_mods_Wei_gnu
export gdasapp_mods=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/GDASApp/modulefiles
#/scratch2/BMC/gsienkf/Tseganeh.Gichamo/jedi/jedimodules.sh
export ufs_mods=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/global-workflow/sorc/ufs_model.fd/modulefiles
# Path to fv3-bundle
export BUILD_DIR=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/GDASApp/build/
#JEDI bin directory where the executables are found
export jedibin=${BUILD_DIR}/bin
export jedi_letkf_exe=$jedibin/fv3jedi_letkf.x
export jedi_hofx_exe=$jedibin/fv3jedi_hofx.x
export jedi_hofx_nm_exe=$jedibin/fv3jedi_hofx_nomodel.x

#local apps dir
export apps_dir=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/APPS/
export apps_bin=$apps_dir/bin
#
export EnsForcGen=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/APPS/stochastic_physics_mod/GenEnsForc.x
#snowDAexec=$apps_dir/snowDA/sorc/driver_snowda
export snowDAexec=$apps_bin/driver_snowda
#export LSMexec=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/ufs_land_drv/ufs-land-driver-mpi-ens/run/ufsLand.exe
export LSMexec=$apps_dir/ufs_land_drv/ufs-land-driver-mpi-ens/run/ufsLand.exe
export exclude_eval=$apps_dir/src/exclude_eval/ExcludeEval.exe
#export vector2tile_exe=${cycle_dir}/vector2tile/vector2tile_converter.exe
export vector2tile_exe=$apps_dir/vector2tile/vector2tile_converter.exe

#export forcing_dir=/scratch2/NCEPDEV/land/data/forcing/gdas/datm/C768/
export forcing_dir=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/FORC/C768/
export obs_src_dir=/scratch2/NCEPDEV/land/data/DA/snow_depth/GHCN/data_proc/v2/
export obs_dest_dir=$cycle_dir/GHCN/
export win_del=-6
export win_len=6
export RES=768
export NPXY=769
export TPATH="/scratch1/NCEPDEV/global/glopara/fix/orog/20220805/C768.mx025_frac/"
export TSTUB="oro_C768.mx025"
export NPZ=64

export rad_infl=120.0      #radius of influence
export back_ser_rad=27.0  # background search radius
export snda_mode=6    # snow DA mode 1 OI Noah 2-7:NoahMP 2 OI, 3 EnKF 4 EnSRF 5 PF 6 add external increment 7 LETKF
export max_obs=50  #max num of snd obs assimilated  at a point/grid cell

export cycle_dir=/scratch1/NCEPDEV/da/Tseganeh.Gichamo/land-offline_workflow
export DADIR=${cycle_dir}/DA_update/
export DAscript=${DADIR}/do_landDA.sh
export work_dir=${cycle_dir}/workdir/
export config_dir=$cycle_dir/config/
export logs_dir=$cycle_dir/logs/
export logs_file=$cycle_dir/logs/letkf_log.log

export analdate=$cycle_dir/analdates.sh
export incdate=$cycle_dir/incdate.sh

base_dir=$(pwd)
export restart_dir=$base_dir
echo "restart dir " $restart_dir "cycle dir" $cycle_dir
cd ${cycle_dir}

export OMP_NUM_THREADS=1
ulimit -s unlimited
ulimit -v unlimited

export I_MPI_EXTRA_FILESYSTEM=on
export I_MPI_EXTRA_FILESYSTEM_LIST=lustre

start_time=$(date +%s)

dates_per_job=60


# read in dates 
source $analdate

logfile=$cycle_dir/cycle.log
touch $logfile
echo "ensemble land and letkf cycling from $startdate to $enddate" >> $logfile

module purge
#source $jedi_mods
#module use $jedi_mods
#module load GDAS/hera
module use $ufs_mods
module load ufs_hera.intel
#module load netcdf/4.7.0
module load netcdf-hdf5parallel/4.7.4
module list

#time srun '--export=ALL' --label -K -n 24 $LSMexec
#time srun '--export=ALL' --label -K -n 12 $snowDAexec
#exit

#echo "running LETKF for snow" >> $logfile
#    #source $jedi_mods
#module purge
#module use $gdasapp_mods
#module load GDAS/hera
#module list
#time srun --label -K -N1 --exclusive -n 1  $jedi_letkf_exe letkf_land_nwa.yaml $logs_dir/letkf.log
#exit

thisdate=$startdate

date_count=0

ens_list=$(seq 20)
mem_list=$(seq -f "%03g" 20)

run_cp () {
    cp ${restart_dir}/ufs-land.namelist ${restart_dir}/ens$1
    cd ${restart_dir}/ens$1
    #time srun '--export=ALL' --label -K -n 6 $LSMexec
    $LSMexec
}
run_v2t () {
    #cp ${restart_dir}/vector2tile.namelist ${restart_dir}/ens$1
    #cd ${restart_dir}/ens$1
    mem_f=$(printf "%03d" $1) 
    tile_path=${cycle_dir}/input/bg/C${RES}/mem${mem_f}
    echo "copying restarts to jedi dir "$tile_path
    rest_file=ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc
    cres_file=${YYYY}${MM}${DD}.${HH}0000.coupler.res

    cp ${cycle_dir}/$cres_file $tile_path
    cp ${cycle_dir}/vector2tile.namelist $tile_path
    cp ${cycle_dir}/ens$1/${rest_file} $tile_path
    
    cd $tile_path
    #sed -i -e "s#XXVPATHXX#${tile_path}/g" vector2tile.namelist
    $vector2tile_exe vector2tile.namelist
    if [[ $? != 0 ]]; then
        echo "vector to tile failed"
	rm $rest_file
        exit 10
    fi
    rm $rest_file
    cd ${cycle_dir}
}
run_t2v (){
    inc_dir=${cycle_dir}/output/letkf/C${RES}/increment/ens$1
    res_dir=${cycle_dir}/ens$1
    rest_file=ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc
    echo "snow increment tile to vector ens member "$1
    cp tile2vector.namelist ${inc_dir}
    cp $res_dir/$rest_file  $inc_dir
    cd ${inc_dir}
    #sed -i -e "s#XXTILERESTPXX#${inc_dir}#g" tile2vector.namelist
    $vector2tile_exe tile2vector.namelist
    cp $inc_dir/$rest_file $res_dir
    cd ${cycle_dir}
}
calc_lnd_incr (){
    mem_f=$(printf "%03d" $1)
    bg_dir=${cycle_dir}/input/bg/C${RES}/mem${mem_f}
    out_dir=${cycle_dir}/output/letkf/C${RES}/restart/mem${mem_f}
    inc_dir=${cycle_dir}/output/letkf/C${RES}/increment/ens$1
    echo "calculating snow incr from background and analyis member "$1
    restp=${YYYY}${MM}${DD}.${HH}0000.sfc_data.tile
    #incp=${YYYY}${MM}${DD}.${HH}0000.sfc_data.tile
    for i in {1..6};do
        ncdiff -O $bg_dir/$restp$i.nc $out_dir/$restp$i.nc $inc_dir/$restp$i.nc;
    done
}
#while [ $thisdate -le $enddate ]; do
while [ $date_count -lt $dates_per_job ]; do

    if [ $thisdate -ge $enddate ]; then
        echo "All done, at date ${thisdate}"  >> $logfile
        end_time=$(date +%s)
        elapsed=$(( end_time - start_time ))
        echo "Elapsed time ${elapsed}"  >> $logfile
        exit 0
    fi

    # substringing to get yr, mon, day, hr info
    export YYYY=`echo $thisdate | cut -c1-4`
    export MM=`echo $thisdate | cut -c5-6`
    export DD=`echo $thisdate | cut -c7-8`
    export HH=`echo $thisdate | cut -c9-10`
#    rest_file=ufs_land_restart.${YYYY}-${MM}-${DD}_${HH}-00-00.nc
    # update model namelist 0-15 hrs
    cp  template.ufs-land.namelist_enkf  ufs-land.namelist
    sed -i -e "s/YYYY/${YYYY}/g" ufs-land.namelist
    sed -i -e "s/MM/${MM}/g" ufs-land.namelist
    sed -i -e "s/DD/${DD}/g" ufs-land.namelist
    sed -i -e "s/HH/${HH}/g" ufs-land.namelist
#    sed -i -e "s/XRHX/23/g" ufs-land.namelist
#    sed -i -e "s/XREFREQX/86400/g" ufs-land.namelist
    
    thisdate=`${incdate} $thisdate 1`
    # substringing to get yr, mon, day, hr info
    export YYYY=`echo $thisdate | cut -c1-4`
    export MM=`echo $thisdate | cut -c5-6`
    export DD=`echo $thisdate | cut -c7-8`
    export HH=`echo $thisdate | cut -c9-10`
    
    #cp template.input.nml input.nml
    cp template.generate_ens_forc.nml generate_ens_forc.nml
    forc_inp_file=C768_GDAS_forcing_${YYYY}-${MM}-${DD}.nc
    sed -i -e "s/FORINPFILE/${forc_inp_file}/g" generate_ens_forc.nml
    sed -i -e "s/YYYY/${YYYY}/g" generate_ens_forc.nml
    sed -i -e "s/MM/${MM}/g" generate_ens_forc.nml
    sed -i -e "s/DD/${DD}/g" generate_ens_forc.nml
    sed -i -e "s/HH/${HH}/g" generate_ens_forc.nml
    sed -i -e "s/XXRESX/${RES}/g" generate_ens_forc.nml
#Make sure the INPUT and RESTART dirs for stochy are in working dir (cycle dir)
# and input.nml has settings right  
    #cp template.input.nml input.nml
    #if [[ $date_count -gt 0 ]]; then
    #    sed -i -e "s/STOCH_INI_VAL/.TRUE./g" input.nml
    #else
    #    sed -i -e "s/STOCH_INI_VAL/.FALSE./g" input.nml
    #fi

    # generate ensemble forcing
    echo 'Running Ens Forc Gen with Stochy' >> $logfile
    #source $EnsForcGenPath/module-setup.sh
    #source ${cycle_dir}/modules_stochy.sh
    #echo $LD_LIBRARY_PATH
    module purge
    module use $ufs_mods
    module load ufs_hera.intel
    #module load netcdf/4.7.0
    module load netcdf-hdf5parallel/4.7.4
    module list

    forc_file=${forcing_dir}/${forc_inp_file}
    for ie in $ens_list      #[@]}"
    do  
        cp ${forc_file} ${cycle_dir}/ens$ie   &
    done
    wait

    time srun '--export=ALL' --label -K -n 240 $EnsForcGen
    if [[ $? != 0 ]]; then
        echo "EnsForc Gen failed"
        exit 10
    fi

    # run  model 0-23 hrs
    echo 'Running model 0-23 hrs' >> $logfile
    #source /home/Tseganeh.Gichamo/.my_mods
    module purge
    module use $ufs_mods
    module load ufs_hera.intel
    module load netcdf-hdf5parallel/4.7.4
    module list
#    for ie in $ens_list  # "${ens_list[@]}"
#    do
#    #    run_cp $ie &
#         cp ${cycle_dir}/LETKF/ens$ie/$rest_file  ${cycle_dir}/ens$ie
#    done
#    wait

    export I_MPI_EXTRA_FILESYSTEM=on 
    export I_MPI_EXTRA_FILESYSTEM_LIST=lustre
    time srun '--export=ALL' --label -K -n 240 $LSMexec
    #time mpiexec -launcher srun -env I_MPI_EXTRA_FILESYSTEM on -env I_MPI_EXTRA_FILESYSTEM_LIST lustre \
    #       -prepend-rank -genvall -n 240 $LSMexec
    if [[ $? != 0 ]]; then
        echo "NoahMP failed"
        exit 10
    fi

    thisdate=`${incdate} $thisdate 23`
#    thisdate=`${incdate} $thisdate 24`
    # substringing to get yr, mon, day, hr info
    export YYYY=`echo $thisdate | cut -c1-4`
    export MM=`echo $thisdate | cut -c5-6`
    export DD=`echo $thisdate | cut -c7-8`
    export HH=`echo $thisdate | cut -c9-10`
    
    cp  ${cycle_dir}/template.vector2tile vector2tile.namelist

    sed -i -e "s/XXYYYY/${YYYY}/g" vector2tile.namelist
    sed -i -e "s/XXMM/${MM}/g" vector2tile.namelist
    sed -i -e "s/XXDD/${DD}/g" vector2tile.namelist
    sed -i -e "s/XXHH/${HH}/g" vector2tile.namelist
    sed -i -e "s/XXRES/${RES}/g" vector2tile.namelist
    sed -i -e "s/XXTSTUB/${TSTUB}/g" vector2tile.namelist
    sed -i -e "s#XXTPATH#${TPATH}#g" vector2tile.namelist
   
    PREVDATE=`${incdate} $thisdate $win_del` 
    #echo "prev_date "$PREVDATE
    echo "prev_date "$PREVDATE >> $logfile
    export YYYP=`echo $PREVDATE | cut -c1-4`
    export MP=`echo $PREVDATE | cut -c5-6`
    export DP=`echo $PREVDATE | cut -c7-8`
    export HP=`echo $PREVDATE | cut -c9-10`    
    cres_file=${YYYY}${MM}${DD}.${HH}0000.coupler.res     
    cp template.coupler.res $cres_file    
    sed -i -e "s/XXYYYY/${YYYY}/g" $cres_file
    sed -i -e "s/XXMM/${MM}/g" $cres_file
    sed -i -e "s/XXDD/${DD}/g" $cres_file
    sed -i -e "s/XXHH/${HH}/g" $cres_file
    sed -i -e "s/XXYYYP/${YYYP}/g" $cres_file
    sed -i -e "s/XXMP/${MP}/g" $cres_file
    sed -i -e "s/XXDP/${DP}/g" $cres_file
    sed -i -e "s/XXHP/${HP}/g" $cres_file
    
    module purge
    module load intel/2022.1.2  impi/2022.1.2
    module load  netcdf-hdf5parallel/4.7.4
    module load nco/5.1.6
    module list

    for ie in $ens_list   #$mem_list   # "${ens_list[@]}"
    do
        run_v2t $ie    &
    done
    wait

    cd ${cycle_dir}
    
    echo "running LETKF for snow"
    echo "running LETKF for snow" >> $logfile
    #source $jedi_mods
    module purge
    module use $gdasapp_mods
    module load GDAS/hera
    module list
    
    cp  template.letkf_land.yaml letkf_snow_C${RES}.yaml
    sed -i -e "s/XXRES/${RES}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXNPX/${NPXY}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXNPY/${NPXY}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXNPZ/${NPZ}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXYYYY/${YYYY}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXMM/${MM}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXDD/${DD}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXHH/${HH}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s#XXTPATH#${TPATH}#g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXTSTUB/${TSTUB}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXYYYP/${YYYP}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXMP/${MP}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXDP/${DP}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXHP/${HP}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXDT/${win_len}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXYYYO/${YYYY}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXMO/${MM}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXDO/${DD}/g" letkf_snow_C${RES}.yaml
    sed -i -e "s/XXHO/${HH}/g" letkf_snow_C${RES}.yaml
   
    time srun --label -K  -n 96 $jedi_letkf_exe letkf_snow_C${RES}.yaml $logs_dir/letkf.log
#    time srun --label -K  -n 1 $jedi_hofx_exe letkf_snow_C${RES}.yaml $logs_dir/letkf.log
     #    # -N1 --exclusive
    if [[ $? != 0 ]]; then
        echo "GDASApp LETKF failed"
        exit 10
    fi
   
#    module purge
#    module load intel/2022.1.2  impi/2022.1.2
#    module load  netcdf-hdf5parallel/4.7.4
#    module load nco/5.1.6
#    module list
#module load intel/2022.1.2  impi/2022.1.2 netcdf-hdf5parallel/4.7.4 nco/5.1.6
#    for ie in $ens_list  # "${ens_list[@]}"
#    do
#        calc_lnd_incr $ie
#    done
#    wait
#
#    cp template.tile2vector tile2vector.namelist
#    sed -i -e "s/XXYYYY/${YYYY}/g" tile2vector.namelist
#    sed -i -e "s/XXMM/${MM}/g" tile2vector.namelist
#    sed -i -e "s/XXDD/${DD}/g" tile2vector.namelist
#    sed -i -e "s/XXHH/${HH}/g" tile2vector.namelist
#    sed -i -e "s/XXRES/${RES}/g" tile2vector.namelist
#    sed -i -e "s/XXTSTUB/${TSTUB}/g" tile2vector.namelist
#    sed -i -e "s#XXTPATH#${TPATH}#g" tile2vector.namelist
#    #call tile to vector on tile increments
#    for ie in $ens_list  # "${ens_list[@]}"
#    do
#        run_t2v $ie
#    done
#    wait

    module purge
    module load intel/2022.1.2  impi/2022.1.2
    module load netcdf-hdf5parallel/4.7.4
    module load nco/5.1.6
    module list

    # update (partition) snow layers with increment 
    cp  template.fort.360 fort.360
    sed -i -e "s/YYYY/${YYYY}/g"  fort.360
    sed -i -e "s/MM/${MM}/g" fort.360
    sed -i -e "s/DD/${DD}/g" fort.360
    sed -i -e "s/HHX/${HH}/g" fort.360
    sed -i -e "s/XRESX/${RES}/g" fort.360
    sed -i -e "s/XRADIX/${rad_infl}/g" fort.360
    sed -i -e "s/XBKSRX/${back_ser_rad}/g" fort.360
    sed -i -e "s/XDAMODX/${snda_mode}/g" fort.360
    sed -i -e "s/XMAXOBSX/${max_obs}/g" fort.360
#    sed -i -e "s#XXINCDIRXX#${incr_dir}/g" fort.360
#    sed -i -e "s/XYYX/${YYYY}/g" fort.360
    
    echo 'Running snowDA with add_ens_increment mode'
    echo 'Running snowDA with add_ens_increment mode' >> $logfile
    time srun '--export=ALL' --label -K -n 240 $snowDAexec
    #-N1-1 --exclusive
    if [[ $? != 0 ]]; then
        echo "snowDAexec failed"
        exit 10
    fi
    # delete forcing ens files
    for ie in $ens_list          #[@]}"
    do
        rm ${cycle_dir}/ens$ie/${forc_inp_file}
    done 
    
    echo "Finished job number, ${date_count},for  date: ${thisdate}"
    echo "Finished job number, ${date_count},for  date: ${thisdate}" >> $logfile

    #thisdate=`${incdate} $thisdate 8`
    date_count=$((date_count+1))

done

# resubmit
if [ $thisdate -le $enddate ]; then
    cd ${cycle_dir}
    echo "export startdate=${thisdate}" > $analdate  #${base_dir}/analdates.sh
    echo "export enddate=${enddate}" >> $analdate    # ${base_dir}/analdates.sh
    # no need to change input.nml for subsequent runs
    #sed -i -e "s/STOCH_INI_VAL/.TRUE./g" template.input.nml
    sbatch submit_cycle_letkf.sh
fi
