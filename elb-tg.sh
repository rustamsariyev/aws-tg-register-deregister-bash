#!/bin/bash

# This script Register or Deregister Targets from TargetGroups.


# Print some info
echo "Please enter required inputs"
echo "Input hints: register = ["reg"] : deregister = ["dereg"] "

# unset variables
unset ELB_NAME
unset REGION_NAME

REGION_NAME="us-east-1"             # US East (N. Virginia)us-east-1
ELB_NAME="TEST-NLB01"               # Default ELB NAME


read -p "Please enter instance name: " TAG_NAME
read -p "Default ELB Name is: ["$ELB_NAME"]. If you want to change, please enter desired ELB name: " NEW_ELB_NAME
read -p "Default Region name is: ["$REGION_NAME"]. If you want to change, please enter desired Region Name: " NEW_REGION_NAME

# Default Values
REGION_NAME="${NEW_REGION_NAME:=$REGION_NAME}"
ELB_NAME="${NEW_ELB_NAME:=$ELB_NAME}"

read -p "Please enter register or deregister: " TARGETS_REG_STATUS
read -p "Please enter service port number: " SVC_PORT

EC2_ID="$(aws ec2 describe-instances --filters Name=tag:Name,Values=$TAG_NAME --region $REGION_NAME --query Reservations[*].Instances[*].[InstanceId] --output text)"

ELB_QUERY="$(aws elbv2 describe-target-groups --region $REGION_NAME | grep $ELB_NAME)"

if [[ -z "$ELB_QUERY" ]]; then

  echo "Invalid ELB Name"

else

  TG_ARN="$(aws elbv2 describe-target-groups --region $REGION_NAME --query "TargetGroups[*].{TargetGroupArn:TargetGroupArn}" --output text)"


  if [[ ! -z "$TG_ARN" ]]; then

    for var_tg_arn in $TG_ARN; do
      TG_ID="$(aws elbv2 describe-target-health --target-group-arn $var_tg_arn --query "TargetHealthDescriptions[*].{TargetID:Target.Id}" --output text --region $REGION_NAME | grep -w $EC2_ID)"
      TG_STATUS="$(
        aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
        --query "TargetHealthDescriptions[*].{TargetHealth:TargetHealth.State, TargetID:Target.Id}" --output text --region $REGION_NAME | grep -w $EC2_ID | awk '{print $1}'
      )"
      TG_NAME="$(echo $var_tg_arn | awk -F "/" '{print $2}')"
      TG_PORT="$(
          aws elbv2 describe-target-groups --target-group-arns $var_tg_arn --query "TargetGroups[*].{Port:Port}" --output text --region $REGION_NAME | grep -w $SVC_PORT
        )"


      if [[ -z $TG_ID ]] && [ "$TARGETS_REG_STATUS" == "reg" ] && [[ "$SVC_PORT" == "$TG_PORT" ]]; then
        echo "Target Not Found"
        echo "Staring to register target"
        aws elbv2 register-targets --target-group-arn $var_tg_arn --targets Id=$EC2_ID --region $REGION_NAME
        sleep 5

        TG_FULL_STATUS="$(
          aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
          --query "TargetHealthDescriptions[*].{TargetID:Target.Id, TargetPort:Target.Port, TargetHealth:TargetHealth.State}" --output text --region $REGION_NAME | grep $EC2_ID
        )"

        echo "TargetGroupName: $TG_NAME - $TG_FULL_STATUS"

      elif [[ -z $TG_ID ]] && [ "$TARGETS_REG_STATUS" == "dereg" ] && [[ "$SVC_PORT" == "$TG_PORT" ]]; then

        echo "Target Not Found"

      else

        if [ "$EC2_ID" == "$TG_ID" ] && [ "$TARGETS_REG_STATUS" == "reg" ] && [ "$SVC_PORT" == "$TG_PORT" ] && [[ "$TG_STATUS" == "healthy" || "$TG_STATUS" == "initial" ]]; then

          TG_FULL_STATUS="$(
            aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
            --query "TargetHealthDescriptions[*].{TargetID:Target.Id, TargetPort:Target.Port, TargetHealth:TargetHealth.State}" --output text --region $REGION_NAME | grep $TG_ID
          )"

          echo "TargetGroupName: $TG_NAME - Target already registered"
          echo "TargetGroupName: $TG_NAME - $TG_FULL_STATUS"

        elif
          [ "$EC2_ID" == "$TG_ID" ] && [ "$TARGETS_REG_STATUS" == "reg" ] && [ "$SVC_PORT" == "$TG_PORT" ] && [ "$TG_STATUS" == "draining" ]
        then
          aws elbv2 register-targets --target-group-arn $var_tg_arn --targets Id=$EC2_ID --region $REGION_NAME
          sleep 5

          TG_FULL_STATUS="$(
            aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
            --query "TargetHealthDescriptions[*].{TargetID:Target.Id, TargetPort:Target.Port, TargetHealth:TargetHealth.State}" --output text --region $REGION_NAME | grep $TG_ID
          )"

          echo "TargetGroupName: $TG_NAME - $TG_FULL_STATUS"

        elif

          [ "$EC2_ID" == "$TG_ID" ] && [ "$TARGETS_REG_STATUS" == "dereg" ] && [ "$SVC_PORT" == "$TG_PORT" ] && [[ "$TG_STATUS" == "healthy" || "$TG_STATUS" == "initial" ]]
        then

          aws elbv2 deregister-targets --target-group-arn $var_tg_arn --targets Id=$EC2_ID --region $REGION_NAME
          sleep 5

          TG_FULL_STATUS="$(
            aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
            --query "TargetHealthDescriptions[*].{TargetID:Target.Id, TargetPort:Target.Port, TargetHealth:TargetHealth.State}" --output text --region $REGION_NAME | grep $TG_ID
          )"

          echo "TargetGroupName: $TG_NAME - $TG_FULL_STATUS"

        elif
          [ "$EC2_ID" == "$TG_ID" ] && [ "$TARGETS_REG_STATUS" == "dereg" ] && [ "$SVC_PORT" == "$TG_PORT" ] && [ "$TG_STATUS" == "draining" ]
        then

          TG_FULL_STATUS="$(
            aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
            --query "TargetHealthDescriptions[*].{TargetID:Target.Id, TargetPort:Target.Port, TargetHealth:TargetHealth.State}" --output text --region $REGION_NAME | grep $TG_ID
          )"

          echo "TargetGroupName: $TG_NAME - Target already deregistered"
          echo "TargetGroupName: $TG_NAME - $TG_FULL_STATUS"

        elif
          [ "$EC2_ID" == "$TG_ID" ] && [ "$SVC_PORT" == "$TG_PORT" ] && [[ "$TG_STATUS" == "unused" || "$TARGETS_REG_STATUS" == "dereg" || "$TARGETS_REG_STATUS" == "reg" ]]
        then

          TG_FULL_STATUS="$(
            aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
            --query "TargetHealthDescriptions[*].{TargetID:Target.Id, TargetPort:Target.Port, TargetHealth:TargetHealth.State}" --output text --region $REGION_NAME | grep $TG_ID
          )"

          echo "TargetGroupName: The target is not registered with a target group, \
          the target group is not used in a listener rule, the target is in an Availability Zone that is not enabled, or the target is in the stopped or terminated state."
          echo "TargetGroupName: $TG_NAME - $TG_FULL_STATUS"

        elif
          [ "$EC2_ID" == "$TG_ID" ] && [ "$SVC_PORT" == "$TG_PORT" ] && [[ "$TG_STATUS" == "unhealthy" || "$TARGETS_REG_STATUS" == "dereg" || "$TARGETS_REG_STATUS" == "reg" ]]
        then

          TG_FULL_STATUS="$(
            aws elbv2 describe-target-health --target-group-arn $var_tg_arn \
            --query "TargetHealthDescriptions[*].{TargetID:Target.Id, TargetPort:Target.Port, TargetHealth:TargetHealth.State}" --output text --region $REGION_NAME | grep $TG_ID
          )"

          echo "The target did not respond to a health check or failed the health check."
          echo "TargetGroupName: $TG_NAME - $TG_FULL_STATUS"

        fi

      fi

    done

  fi

fi
