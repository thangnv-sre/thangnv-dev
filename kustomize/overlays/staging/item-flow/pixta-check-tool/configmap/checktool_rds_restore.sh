#!/bin/bash
# 0755
. /aws/functions
. /aws/config/checktool_db_info

# source ./functions
# source ./checktool_db_info

# initialize
setup

# lockfile check
check_locked

TODAY=$(date '+%y%m%d')
SN_NAME="${TODAY}01"
AUTO_BACKUP_DATE=$(date -d '1 day ago' '+%Y-%m-%d')
AUTO_SN_PREFIX="rds:${DB_INSTANCE_NAME}-${AUTO_BACKUP_DATE}"
YESTERDAY=$(date -d '1 day ago' '+%y%m%d')
FIVEDAYSAGO=$(date -d '7 day ago' '+%y%m%d')
PROFILE="pixta-production"
VN_PROFILE="pixtavietnam"

export AWS_RDS_HOME=/opt/aws/apitools/rds
export JAVA_HOME=/usr/lib/jvm/jre
export PATH=/opt/aws/bin:$PATH

usage() {
    echo "Usage $0"
    exit 0
}
TEST=$(aws rds describe-db-snapshots --profile $PROFILE | grep "${AUTO_SN_PREFIX}")
echo ${TEST}
# AUTO_SNAPSHOT_NAME=$(aws rds describe-db-snapshots --profile $PROFILE | grep "${AUTO_SN_PREFIX}" | awk NR==2 | awk '{print $2}' | sed 's/"//g' | sed 's/.$//') 
AUTO_SNAPSHOT_NAME=$(aws rds describe-db-snapshots --profile $PROFILE | grep "${AUTO_SN_PREFIX}" | awk '{print $6}' | grep "rds")
echo ${AUTO_SNAPSHOT_NAME}
SHARED_SNAPSHOT_NAME=$(sed -e 's#.*:\(\)#\1#' <<<"${AUTO_SNAPSHOT_NAME}-shared")
echo ${SHARED_SNAPSHOT_NAME}
SHARED_SNAPSHOT_ARN="${SNAPSHOT_RESOURCE_NAME}:${SHARED_SNAPSHOT_NAME}"
echo ${SHARED_SNAPSHOT_ARN}

check_snapshot() {
    while :; do
        aws rds describe-db-snapshots --profile $PROFILE | grep "${AUTO_SNAPSHOT_NAME}"
        STATUS=$?
        echo ${AUTO_SNAPSHOT_NAME}
        echo ${STATUS}
        if [ $STATUS -eq 0 ]; then
            echo "Check automated snapshot successful. DB snapshot Identifier ${AUTO_SNAPSHOT_NAME}"
            break
        else
            sleep 60
        fi
    done
}

restore_from_snapshot() {
    aws rds restore-db-instance-from-db-snapshot \
        --db-instance-identifier $DB_INSTANCE_NAME-$SN_NAME-vpc \
        --db-snapshot-identifier $SHARED_SNAPSHOT_ARN \
        --db-instance-class $VPC_CLASS \
        --port 3306 \
        --iops 0 \
        --db-subnet-group-name eks-staging-public \
        --profile $VN_PROFILE

    while :; do
        aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_NAME-$SN_NAME-vpc --profile $VN_PROFILE | grep "available"
        STATUS=$?
        if [ $STATUS -eq 0 ]; then
            echo "Restore from $SHARED_SNAPSHOT_NAME successful. DB instance Identifier $DB_INSTANCE_NAME-${SN_NAME}-vpc"
            break
        else
            sleep 60
        fi
    done
}

modify_db_instance() {
    aws rds modify-db-instance \
        --db-instance-identifier $DB_INSTANCE_NAME-${SN_NAME}-vpc \
        --vpc-security-group-ids sg-0f91f45ab164780d0 \
        --backup-retention-period 0 \
        --apply-immediately \
        --publicly-accessible \
        --profile $VN_PROFILE

    while :; do
        aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_NAME-${SN_NAME}-vpc --profile $VN_PROFILE | grep "sg-0f91f45ab164780d0" && aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_NAME-${SN_NAME}-vpc --profile $VN_PROFILE | grep "available"
        STATUS=$?
        if [ $STATUS -eq 0 ]; then
            echo "modify db instance successful. DB instance Identifier $DB_INSTANCE_NAME-${SN_NAME}-vpc"
            break
        else
            sleep 60
        fi
    done
}

rename_snapshot_to_staging() {
    aws rds modify-db-instance \
        --db-instance-identifier $DB_INSTANCE_NAME-${SN_NAME}-vpc \
        --new-db-instance-identifier $DB_INSTANCE_NAME-vpc \
        --backup-retention-period 1 \
        --apply-immediately \
        --profile $VN_PROFILE

    while :; do
        aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_NAME-vpc --profile $VN_PROFILE | grep "available"
        STATUS=$?
        if [ $STATUS -eq 0 ]; then
            echo "modify db instance successful. DB instance Identifier $DB_INSTANCE_NAME-vpc"
            break
        else
            sleep 60
        fi
    done
}

update_for_masking() {
    case "$1" in
    PIXTA)
        DATABASE=$PIXTA_DB_NAME
        ;;
    CHECKTOOL)
        DATABASE=$CHECKTOOL_DB_NAME
        ;;
    *)
        error "masking table not found."
        exit 1
        ;;
    esac
    db_name=$1
    masktables="${db_name}_MASKING_TABLES"
    eval masktables=\"\$${masktables}\"

    while :; do
        mysql $MYSQL_ARGS -h pixta-check-tool-vpc.cyqbfzctkesh.ap-northeast-1.rds.amazonaws.com $DATABASE -e "update accounts set name='xxxx'"
        LOGIN_STATUS=$?
        if [ $LOGIN_STATUS -eq 0 ]; then
            echo "db instance update success."
            for tbls in $masktables; do
                tmp="${db_name}_${tbls}_masking_field"
                eval tmp=\"\$${tmp}\"
                for setdata in ${tmp}; do
                    field=${setdata%:*}
                    mask=${setdata#*:}
                    echo $mask | grep ^concat >/dev/null
                    if [ $? -eq 0 ]; then
                        mysql $MYSQL_ARGS -h pixta-check-tool-vpc.cyqbfzctkesh.ap-northeast-1.rds.amazonaws.com $DATABASE -e "update $tbls set $field=${mask}"
                        MASK_STATUS=$?
                    else
                        mysql $MYSQL_ARGS -h pixta-check-tool-vpc.cyqbfzctkesh.ap-northeast-1.rds.amazonaws.com $DATABASE -e "update $tbls set $field='${mask}'"
                        MASK_STATUS=$?
                    fi
                    if [ $MASK_STATUS -eq 0 ]; then
                        info "masking successful. masking field $field at $tbls on $DATABASE"
                    else
                        error "masking failed. masking field $field at $tbls on $DATABASE"
                    fi
                done
            done
            break
        else
            sleep 60
        fi
    done
}

delete_db_instance() {
    DB_ID=$1
    yes | aws rds delete-db-instance --db-instance-identifier $DB_ID --skip-final-snapshot --profile $VN_PROFILE

    while :; do
        aws rds describe-db-instances --db-instance-identifier $DB_ID --profile $VN_PROFILE | grep "available"
        STATUS=$?
        if [ $STATUS -ne 0 ]; then
            echo "Delete db instance successful. DB instance Identifier $DB_ID"
            break
        else
            sleep 60
        fi
    done
}

copy_db_snapshot() {
    yes | aws rds copy-db-snapshot --source-db-snapshot-identifier $AUTO_SNAPSHOT_NAME --target-db-snapshot-identifier $SHARED_SNAPSHOT_NAME --profile $PROFILE

    while :; do
        aws rds describe-db-snapshots --profile $PROFILE --output text | grep "${SHARED_SNAPSHOT_NAME}" | grep "available"
        STATUS=$?
        if [ $STATUS -eq 0 ]; then
            echo "copy automated snapshot successful. DB snapshot Identifier for sharing ${SHARED_SNAPSHOT_NAME}"
            break
        else
            sleep 60
        fi
    done
}

share_db_snapshot() {
    yes | aws rds modify-db-snapshot-attribute --db-snapshot-identifier $SHARED_SNAPSHOT_NAME --attribute-name restore --values-to-add {"045675425505","567351176096"} --profile $PROFILE
    echo "Shared snapshot successful"
}

delete_shared_snapshot() {
    yes | aws rds delete-db-snapshot --db-snapshot-identifier $SHARED_SNAPSHOT_NAME --profile $PROFILE

    while :; do
        aws rds describe-db-snapshots --profile $PROFILE --output text | grep "${SHARED_SNAPSHOT_NAME}" | grep "available"
        STATUS=$?
        if [ $STATUS -ne 0 ]; then
            echo "delete shared snapshot successful. DB snapshot Identifier ${SHARED_SNAPSHOT_NAME}"
            break
        else
            sleep 60
        fi
    done
}

add_tags() {
    DB_ID=$1

    for tags in $TAGS_VAL; do
        key=${tags%:*}
        value=${tags#*:}

        aws rds add-tags-to-resource --resource-name $RESOURCE_NAME:$DB_ID --tags Key=${key},Value=${value} --profile $VN_PROFILE
        if [ $? -eq 0 ]; then
            echo "add tags successful. key:$key, value:$value"
        else
            error "add tags failed. key:$key, value:$value"
        fi
    done
}

stop_db_instance() {
    aws rds stop-db-instance --db-instance-identifier $DB_INSTANCE_NAME-vpc --profile $VN_PROFILE

    while :; do
        aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_NAME-vpc --profile $VN_PROFILE | grep "stop"
        STATUS=$?
        if [ $STATUS -eq 0 ]; then
            echo "stop db instance successful. DB instance Identifier $DB_INSTANCE_NAME-vpc"
            break
        else
            sleep 60
        fi
    done
}

lock
echo "$0 started."  
check_snapshot
delete_db_instance $DB_INSTANCE_NAME-vpc
copy_db_snapshot
share_db_snapshot
restore_from_snapshot
modify_db_instance
# sleep 1800
rename_snapshot_to_staging
update_for_masking CHECKTOOL
# stop_db_instance
add_tags $DB_INSTANCE_NAME-vpc
delete_shared_snapshot
echo "$0 finished."
unlock
exit 0
