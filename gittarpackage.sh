#!/bin/bash
#
# GPL-2.0-only
# Author: Louis Wang <wluhua@gmail.com>
# Description: script to update last commit date on version file, and build new tar package with git archive.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#
# Copyright (C) 2017 Louis Wang <wluhua@gmail.com>
#

# __version__ = "1.0.1.0.170405"
# 
# Note: format of version file:  
#     version="$major.$maintenance.$minor_or_component.$patch_set.$last_commit_date"
#     e.g. gittarpackage.version=1.0.1.0.170330
# 
#   tarball name: ${REPO_HOME}/${REPO_NAME}-${version}.tar.gz
#

########################################
#
# Variables
#
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/sfw/bin/
LC_ALL=C
export PATH LC_AL

REPO_HOME="/var/tmp/git-repo"
FILESUFFIX="tar.gz"

PROG="`basename $0`"
PROG_HOME="$(dirname $(readlink -f $0))"
WORK_DIR=$(pwd || echo $PWD)
hostn=`hostname`
typeset=gittarpackage
minute=`TZ=":America/Los_Angeles" date +'%Y%m%d%H%M'`
log_file=/tmp/${typeset}_${hostn}_$minute.log
FSNADMIN_APS_DIR="/var/tmp/${typeset}"
# tmp_file=$(echo /tmp/$$.${typeset})
# timestamp=`date -u +'%Y-%m-%d %H:%M:%S'`

########################################
#
# Subroutines
#
info() {
   echo "INFO: $1" ;
}

warn() {
   echo "WARN: $1" 1>&2;
}

error() {
   echo "ERROR: $1" 1>&2;
   echo "Exit Code: 1"
   #[ ! -f /usr/bin/flock ] && trap_clean_up
   exit 1;
}

debug() {
   [ -n "$DEBUG" ] && echo -e "DEBUG: $@" 1>&2;
}

usage() {
    local _args=$1
    local _rsult=""
    _rsult="
-E- Missing option
NAME:
  gittarpackage.sh - Update last commit date on version file and build tarball with git archive
    
SYNOPSIS:
  gittarpackage.sh [Options]
  
DESCRIPTION:
  Update last commit date on version file, build new tar package with git archive,
  and scp the new tarball to tarball repos.
  
OPTIONS: 
  --branch <branch_or_tag_name>
  -u # Update last_commit_date on version. If version file if it not exist.
  --clone_path <CLONE_PATH>
    # the ssh path of remote git repo with your username. 
  --repo_home <REPO_HOME>
    # default: /var/tmp/git-repo, it used used with CLONE_PATH
  --scp_path <scp_path>
    # locatioin when you want to archive the tarball
  --user <USER>
  --product_name <PRODUCT_NAME>
    # tarball bundle name

EXAMPLES:
  gittarpackage.sh --branch "tags/1.0.1.0.180330"  
  gittarpackage.sh -u

  gittarpackage.sh -u --repo_home /home/luhwang/git-repos \\
    --clone_path ssh://xxxx/xxxx.git \\
    --branch master \\
    --scp_path root@xxxx:/export/test_repo/repo/sre-tools/
 
BUGS:
  
     "
    printf "%s\n" "$_rsult"
    exit 2
}

########################################
get_repo_name(){
    local _rc=0
    if [ -n "$CLONE_PATH" ]
    then
        _REPO_NAME=$(echo "$CLONE_PATH" |awk -F"/" '{print $NF}' |sed 's/.git$//g')
    else
        _REPO_NAME=$(git remote -v |tr '/' ' ' |awk '{print $(NF-1)}'|head -1 |sed 's/.git$//g')    
    fi
    echo $_REPO_NAME
    return $_rc
}

get_repo_dir(){
    local _rc=0
    if [ -n "$CLONE_PATH" ]
    then
        _REPO_DIR=${REPO_HOME}/${REPO_NAME}
    else
        _REPO_DIR=$(git rev-parse --show-toplevel )
    fi
    echo $_REPO_DIR
    return $_rc
}

get_repo_home(){
    local _rc=0
    if [ -n "$CLONE_PATH" ]
    then
        _REPO_HOME=${REPO_HOME}
    else
        _REPO_DIR=$(git rev-parse --show-toplevel )
        _REPO_HOME=$(dirname $_REPO_DIR)
    fi
    echo $_REPO_HOME
    return $_rc
}

get_branch(){
    local _rc=0
    if [ -n "$BRANCH" ]
    then
        echo $BRANCH
    else
        _BRANCH=$(git branch | grep "*" | cut -d ' ' -f2- | head -1 |sed '/no branch/d')
        _tag=$(git describe --tags | head -1 | grep -vi 'No tags')
        _remote=$(git describe --all |grep "heads\|remotes" |head -1 |sed 's/heads/origin/g; s/^remotes\///g')

        if [ -n "$_BRANCH" ]
        then
            :
        elif [ -n "$_remote" ]
        then
            _BRANCH=${_remote}
        elif  [ -n "$_tag" ]
        then
            _BRANCH=tags/${_tag}
        fi
        echo $_BRANCH
    fi
    return $_rc
}

git_pull(){
    # git clone
    local _rc=0
    set -x
    if [ -n "$CLONE_PATH" ] && [ ! -d "$REPO_NAME" ]
    then
        mkdir -p ${REPO_HOME}
        cd ${REPO_HOME}
        # REPO_NAME=$(echo "$CLONE_PATH" |awk -F"/" '{print $NF}' |sed 's/.git$//g')
        git clone $CLONE_PATH
        cd $REPO_NAME
        git pull
        _rc=$?
    fi
    
    # switch to the branch or tag
    if [ -n "$BRANCH" ]
    then
        # git branch -a
        # git tag -l |sort -n |tail -1
        cd ${REPO_HOME}; 
        cd ${REPO_NAME}
        git fetch --all --tags --prune
        git checkout $BRANCH
        git pull
        _rc=$?
    fi
    set +x
    return $_rc
}

get_current_branch_version(){
    local _rc=0
    cd $REPO_DIR
    
    if [[ $BRANCH == "tags/"* ]]
    then
        last_commit_date=$(TZ=UTC git show --format="%cd" $BRANCH --date=short | sed '/^$/d' |tail -1 | sed 's/-//g;s/^..//g')
    else
        last_commit_date=$(TZ=UTC git show --format="%cd" $BRANCH --date=short| head -1 |sed 's/-//g;s/^..//g')
    fi
    
    if [ -n "$previous_version" ]
    then
        major=$(echo "$previous_version" |awk -F. '{print $(NF-4)}')
        maintenance=$(echo "$previous_version" |awk -F. '{print $(NF-3)}')
        minor_or_component=$(echo "$previous_version" |awk -F. '{print $(NF-2)}')
        patch_set=$(echo "$previous_version" |awk -F. '{print $(NF-1)}')
        #last_commit_date=
    fi

    [ -z "$major" ] && major=1
    [ -z "$maintenance" ] && maintenance=0
    [ -z "$minor_or_component" ] && minor_or_component=0
    [ -z "$patch_set" ] && patch_set=0

    _version="$major.$maintenance.$minor_or_component.$patch_set.$last_commit_date"
    echo $_version
    return $_rc
}

########################################
git_commit_version_file(){
    # Update version number
    local _rc=0
    # REPO_NAME=$(git remote -v |tr '/' ' ' |awk '{print $(NF-1)}'|head -1 |sed 's/.git$//g')    
    if  [ -n "$PUSH_VERSION" ] && [[ $previous_version != $version ]] && [[ "$BRANCH" != "tags"* ]]
    then
        p_last_commit_date=$(echo $previous_version |head -1 |awk -F. '{print $NF}')
        n_last_commit_date=$(echo $version |head -1 |awk -F. '{print $NF}')
        if [ -n "$p_last_commit_date" ] && [ $p_last_commit_date -ge $n_last_commit_date ]
        then
            info "$REPO_NAME:$BRANCH: Skip: git_commit_version_file ($p_last_commit_date -ge $n_last_commit_date)"
        else
            info "Issuing Command: git commit -m \"Update version file - \$version\""
            echo "$REPO_NAME.version=$version" > version
            git add ./version	
            git commit -m "Update version file - $version"
            # git push -u origin master
            # git pull origin
            git push -u origin $BRANCH
            _rc=$?
        fi
        
    else
        info "$REPO_NAME:$BRANCH: Skip: git_commit_version_file"
    fi
    return $_rc

}

########################################
git_archive() {
    local _rc=0
    echo "INFO: Issuing Command: git archive $BRANCH --format=tar --prefix=${REPO_NAME}/ ./ > ${REPO_HOME}/${REPO_NAME}-${version}.tar"
    [ -f ${REPO_HOME}/${REPO_NAME}-${version}.tar ] && rm -f ${REPO_HOME}/${REPO_NAME}-${version}.tar 
    [ -f $tarball ] && mv $tarball $tarball.old
    
    cd ${REPO_HOME}; 
    cd ${REPO_NAME}
    #git tag
    #git status
    
    # git archive --format=tar --prefix=aps-check/ tags/1.0.1.0.180312 > /home/luhwang/git-repos/aps-check-1.0.1.0.180329-test.tar
    git archive $BRANCH --format=tar --prefix=${REPO_NAME}/ ./ > ${REPO_HOME}/${REPO_NAME}-${version}.tar
    # git archive $BRANCH --format=tar --prefix=${REPO_NAME}/ HEAD > ${REPO_HOME}/${REPO_NAME}-${version}.tar
    _rc=$?
    if [ $_rc -eq 0 ]
    then
        gzip ${REPO_HOME}/${REPO_NAME}-${version}.tar
        _rc=$?
    fi
    return $_rc
}

########################################
untar_file(){
    # untar files for md5sum
    # Usage: untar_file "${FSNADMIN_APS_DIR}" "$tarball"
    local _rc=0
    _DIR=$1
    _FILENAME=$2
    [ -d $_DIR ] && rm -rf $_DIR
    mkdir -p $_DIR
    cd $_DIR
    tar -xvf $_FILENAME
    _rc=$?
    return $_rc
}

########################################
create_md5sum_file(){
    # create the file with md5sum
    # Usage: create_md5sum_file "${FSNADMIN_APS_DIR}" "${REPO_NAME}-${version}.${FILESUFFIX}"
    local _rc=0
    _DIR=$1
    _FILENAME=$(echo $2 |awk -F"/" '{print $NF}')
    if [ -d $_DIR ]
    then
        cd $_DIR
        find ./ -type f | xargs md5sum |sed '/md5sum/d' > ${_FILENAME}.md5sum
        cp ${_FILENAME}.md5sum ${REPO_HOME}/${_FILENAME}.md5sum.$minute
        _rc=$?        
    else
        warn "$REPO_NAME:$BRANCH: dir not found: $_DIR"
    fi
    return $_rc
}

########################################
verification_latest_tarball(){
    # Check if latest.tar.gz is a new tarball or not
    local _rc=0
    WC1=$(ls ${REPO_HOME}/${REPO_NAME}-*.${FILESUFFIX}.md5sum* |grep ${REPO_NAME}|sort |tail -2 |wc -l)
    WC2=$(ls ${REPO_HOME}/${REPO_NAME}-*.${FILESUFFIX}.md5sum* |grep ${REPO_NAME}|sort |tail -2 |xargs md5sum | awk '{print $1}' | uniq |wc -l)

    if [ $WC1 -eq 1 ] ||  [ $WC2 -eq 2 ]
    then
        ########################################
        # no same tar found.
        IS_NEW_VERSION=IS_NEW_VERSION
        [ -f $tarball_short ] && rm -f $tarball_short
        [ -f ${REPO_HOME}/${REPO_NAME}.tar ] && rm -f ${REPO_HOME}/${REPO_NAME}.tar
        if [ -f $tarball ]
        then
            ln $tarball $tarball_short
            _rc=$?
            info "$REPO_NAME:$BRANCH: Package created: $tarball, $tarball_short"
        elif [ -f ${REPO_HOME}/${REPO_NAME}-${version}.tar ]
        then
            ln ${REPO_HOME}/${REPO_NAME}-${version}.tar ${REPO_HOME}/${REPO_NAME}.tar
            _rc=$?
            info "$REPO_NAME:$BRANCH: Package created: ${REPO_HOME}/${REPO_NAME}-${version}.tar, ${REPO_HOME}/${REPO_NAME}.tar"
        else
            warn "$REPO_NAME:$BRANCH: Failed to create tar file $tarball"
            _rc=1
        fi
    else
        ########################################
        # same tarball with same version found.
        info "$REPO_NAME:$BRANCH: Skip: verification_latest_tarball - no new verison found"
        [ -f ${REPO_HOME}/${REPO_NAME}-${version}.tar ] && rm -f ${REPO_HOME}/${REPO_NAME}-${version}.tar
        [ -f $tarball ] && rm -f $tarball
        [ -f $tarball.md5sum.$minute ] && rm -f $tarball.md5sum.$minute
        [ -f ${REPO_HOME}/${_FILENAME}.md5sum.$minute ] && rm -f ${REPO_HOME}/${_FILENAME}.md5sum.$minute        
        
    fi
    
    if [ -f $tarball ]
    then
        [ -f $tarball.old ] && rm -f $tarball.old
    else
        [ -f $tarball.old ] && mv $tarball.old $tarball
    fi
    return $_rc
}

########################################
scp_latest_tarball_to_remote_repo(){
    # sync tarball to remote tarball repo
    local _rc=0
    if [ -n "$IS_NEW_VERSION" ] && [ -n "$SCP_PATH" ] && [ -f $tarball ]
    then
        echo "INFO: scp $tarball_short $SCP_PATH"
        scp $tarball $SCP_PATH
        scp $tarball_short $SCP_PATH
        _rc=$?
        if `echo "$SCP_PATH" |grep -q "test_repo/sre-tools"`
        then
            _FILENAME=$(echo $tarball |awk -F"/" '{print $NF}')
            info "$REPO_NAME:$BRANCH: latest tarball: http://xxxxx/${_FILENAME}"
        fi
    else
        info "$REPO_NAME:$BRANCH: Skip: scp_latest_tarball_to_remote_repo"
    fi
    return $_rc
}

########################################
clean_up() {
    local _rc=0
    cd ${WORK_DIR} 
    [ -d ${FSNADMIN_APS_DIR} ] && rm -rf ${FSNADMIN_APS_DIR}
    return $_rc
}


########################################
bundle_xxxxx(){
:
}


########################################
## Parse the arguments:
ARGUMENTS="$@"
while [ $# -gt 0 ]
do
  case "$1" in  
        --*)    
          k1=$(echo $1 |tr '[:lower:]' '[:upper:]'); 
          k1=${k1:2}; 
          eval "$k1=$2";
          [ "${2:0:1}" = "-" ] && usage 1; 
          shift;;            
        -u)      PUSH_VERSION=True; shift 0;; 
        -d|--debug)      DEBUG="ON"; VERBOSE="1";         shift 0;; 
        -v)              VERBOSE="1";                     shift 0;; 
        -vv*)            VERBOSE="2";                     shift 0;; 
        -h|--man|--help) usage;                           exit 0;;
        *)               warn "Unknow arguments: \"$1\""; exit 1;;
  esac
  shift
done

########################################
# MAIN

[ -f $PROG_HOME/verison ] && cat $PROG_HOME/verison

mkdir -p ${REPO_HOME}
mkdir -p ${FSNADMIN_APS_DIR}
if [ -n "$CLONE_PATH" ]
then
    cd ${REPO_HOME}
fi

if [ -z "$BUNDLE" ]
then
    echo "-------------------------------------------------------------------"
    REPO_NAME=$(get_repo_name)
    REPO_DIR=$(get_repo_dir)
    REPO_HOME=$(get_repo_home)
    BRANCH=$(get_branch)
    info "$REPO_NAME:$BRANCH: REPO_HOME = $REPO_HOME"
    info "$REPO_NAME:$BRANCH: CLONE_PATH= $CLONE_PATH"
    info "$REPO_NAME:$BRANCH: BRANCH    = $BRANCH"
    info "$REPO_NAME:$BRANCH: REPO_DIR  = $REPO_DIR"
    info "$REPO_NAME:$BRANCH: SCP_PATH  = $SCP_PATH"

    git_pull
    
    if [ -n "$REPO_DIR" ] && [ -d $REPO_DIR ]
    then
        :
    else
        error "$REPO_NAME:$BRANCH: Not able to get REPO_DIR. Pleae run this script in git repo folder."
        exit 1
    fi
    
    cd $REPO_DIR 
    
    previous_version=$(cat $REPO_DIR/version 2>/dev/null |awk -F"=" '{print $NF}')
    version=$(get_current_branch_version)
    tarball=${REPO_HOME}/${REPO_NAME}-${version}.${FILESUFFIX}
    tarball_short=${REPO_HOME}/${REPO_NAME}.${FILESUFFIX}
    info "$REPO_NAME:$BRANCH: previous_version = $previous_version"
    info "$REPO_NAME:$BRANCH: version   = $version"
    info "$REPO_NAME:$BRANCH: tarball   = $tarball"
    
    git_commit_version_file
    [ $? != 0 ] && error "$REPO_NAME:$BRANCH: Failed on previous step(git_commit_version_file). Exit 1" 

    git_archive
    [ $? != 0 ] && error "$REPO_NAME:$BRANCH: Failed on previous step(git_archive). Exit 1" 

    untar_file ${FSNADMIN_APS_DIR} $tarball
    [ $? != 0 ] && error "$REPO_NAME:$BRANCH: Failed on previous step(untar_file). Exit 1" 

    create_md5sum_file ${FSNADMIN_APS_DIR} $tarball
    [ $? != 0 ] && error "$REPO_NAME:$BRANCH: Failed on previous step(create_md5sum_file). Exit 1" 

    verification_latest_tarball
    [ $? != 0 ] && error "$REPO_NAME:$BRANCH: Failed on previous step(verification_latest_tarball). Exit 1" 

    scp_latest_tarball_to_remote_repo
    [ $? != 0 ] && error "$REPO_NAME:$BRANCH: Failed on previous step(scp_latest_tarball_to_remote_repo). Exit 1" 

    clean_up
    [ $? != 0 ] && error "$REPO_NAME:$BRANCH: Failed on previous step(clean_up). Exit 1" 
    
elif [[ $BUNDLE == *xxxxx* ]]
then
    bundle_xxxxx
    [ $? != 0 ] && error "Failed on previous step(bundle_xxxxx). Exit 1" 
fi
exit 0
# end.
