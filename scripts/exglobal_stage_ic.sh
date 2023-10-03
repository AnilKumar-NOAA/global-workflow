#!/usr/bin/env bash

source "${HOMEgfs}/ush/preamble.sh"

# Locally scoped variables and functions
# shellcheck disable=SC2153
GDATE=$(date --utc -d "${PDY} ${cyc} - ${assim_freq} hours" +%Y%m%d%H)
gPDY="${GDATE:0:8}"
gcyc="${GDATE:8:2}"

MEMDIR_ARRAY=()
if [[ "${RUN}" == "gefs" ]]; then
  # Populate the member_dirs array based on the value of NMEM_ENS
  for ((ii = 0; ii < "${NMEM_ENS}"; ii++)); do
    MEMDIR_ARRAY+=("mem$(printf "%03d" "${ii}")")
  done
else
  MEMDIR_ARRAY+=("")
fi

# Initialize return code
err=0

error_message() {
  echo "FATAL ERROR: Unable to copy ${1} to ${2} (Error code ${3})"
}

###############################################################
for MEMDIR in "${MEMDIR_ARRAY[@]}"; do
  # Stage the FV3 initial conditions to ROTDIR (cold start)
  YMD=${PDY} HH=${cyc} generate_com -r COM_ATMOS_INPUT
  [[ ! -d "${COM_ATMOS_INPUT}" ]] && mkdir -p "${COM_ATMOS_INPUT}"
  src="${BASE_CPLIC}/${CPL_ATMIC}/${YMD}${HH}/${MEMDIR}/atmos/gfs_ctrl.nc"
  tgt="${COM_ATMOS_INPUT}/gfs_ctrl.nc"
  ${NCP} "${src}" "${tgt}"
  rc=$?
  ((rc != 0)) && error_message "${src}" "${tgt}" "${rc}"
  err=$((err + rc))
  for ftype in gfs_data sfc_data; do
    for tt in $(seq 1 6); do
      src="${BASE_CPLIC}/${CPL_ATMIC}/${YMD}${HH}/${MEMDIR}/atmos/${ftype}.tile${tt}.nc"
      tgt="${COM_ATMOS_INPUT}/${ftype}.tile${tt}.nc"
      ${NCP} "${src}" "${tgt}"
      rc=$?
      tgt="${COM_ATMOS_INPUT}/${ftype}.tile${tt}.nc"
      ${NCP} "${src}" "${tgt}"
      rc=$?
      ((rc != 0)) && error_message "${src}" "${tgt}" "${rc}"
      err=$((err + rc))
    done
  done

  # Stage ocean initial conditions to ROTDIR (warm start)
  if [[ "${DO_OCN:-}" = "YES" ]]; then
    YMD=${gPDY} HH=${gcyc} generate_com -r COM_OCEAN_RESTART
    [[ ! -d "${COM_OCEAN_RESTART}" ]] && mkdir -p "${COM_OCEAN_RESTART}"
    src="${BASE_CPLIC}/${CPL_OCNIC}/${PDY}${cyc}/${MEMDIR}/ocean/${OCNRES}/MOM.res.nc"
    tgt="${COM_OCEAN_RESTART}/${PDY}.${cyc}0000.MOM.res.nc"
    ${NCP} "${src}" "${tgt}"
    rc=$?
    [[ ${rc} -ne 0 ]] && error_message "${src}" "${tgt}" "${rc}"
    err=$((err + rc))
    case "${OCNRES}" in
      "500" | "100") # Only 5 degree or 1 degree ocean does not have MOM.res_[1-4].nc files
        ;;
      "025") # Only 1/4 degree ocean has MOM.res_[1-4].nc files
        for ((nn = 1; nn <= 4; nn++)); do
          src="${BASE_CPLIC}/${CPL_OCNIC}/${PDY}${cyc}/${MEMDIR}/ocean/${OCNRES}/MOM.res_${nn}.nc"
          if [[ -f "${src}" ]]; then
            tgt="${COM_OCEAN_RESTART}/${PDY}.${cyc}0000.MOM.res_${nn}.nc"
            ${NCP} "${src}" "${tgt}"
            rc=$?
            [[ ${rc} -ne 0 ]] && error_message "${src}" "${tgt}" "${rc}"
            err=$((err + rc))
          fi
        done
        ;;
      *)
        echo "FATAL ERROR: Unsupported ocean resolution ${OCNRES}"
        rc=1
        err=$((err + rc))
        ;;
    esac
  fi
  # Stage ice initial conditions to ROTDIR (warm start)
  if [[ "${DO_ICE:-}" = "YES" ]]; then
    YMD=${gPDY} HH=${gcyc} generate_com -r COM_ICE_RESTART
    [[ ! -d "${COM_ICE_RESTART}" ]] && mkdir -p "${COM_ICE_RESTART}"
    src="${BASE_CPLIC}/${CPL_ATMIC}/${YMD}${HH}/${MEMDIR}/ice/${PDY}.${cyc}0000.cice_model.res.nc"
    tgt="${COM_OCEAN_RESTART}/${PDY}.${cyc}0000.cice_model.res.nc"
    ${NCP} "${src}" "${tgt}"
    rc=$?
    ((rc != 0)) && error_message "${src}" "${tgt}" "${rc}"
    err=$((err + rc))
  fi

  # Stage the WW3 initial conditions to ROTDIR (warm start; TODO: these should be placed in $RUN.$gPDY/$gcyc)
  if [[ "${DO_WAVE:-}" = "YES" ]]; then
    YMD=${PDY} HH=${cyc} generate_com -r COM_WAVE_RESTART
    [[ ! -d "${COM_WAVE_RESTART}" ]] && mkdir -p "${COM_WAVE_RESTART}"
    for grdID in ${waveGRD}; do # TODO: check if this is a bash array; if so adjust
      src="${BASE_CPLIC}/${CPL_WAVIC}/${PDY}${cyc}/${MEMDIR}/wave/${grdID}/${PDY}.${cyc}0000.restart.${grdID}"
      tgt="${COM_WAVE_RESTART}/${PDY}.${cyc}0000.restart.${grdID}"
      ${NCP} "${src}" "${tgt}"
      rc=$?
      ((rc != 0)) && error_message "${src}" "${tgt}" "${rc}"
      err=$((err + rc))
    done
  fi

done # for MEMDIR in "${MEMDIR_ARRAY[@]}"; do
###############################################################
# Check for errors and exit if any of the above failed
if [[ "${err}" -ne 0 ]]; then
  echo "FATAL ERROR: Unable to copy ICs from ${BASE_CPLIC} to ${ROTDIR}; ABORT!"
  exit "${err}"
fi

##############################################################
# Exit cleanly
exit "${err}"
