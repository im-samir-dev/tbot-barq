#!/usr/bin/bash

# set -x

typeset -A env
typeset -A user_ids

function set_variables() {
  while IFS== read -r line; do
      local key=$(echo $line | grep -Eo '^[^=]+')
      local value=$(echo $line | grep -Eo '=.*$')
      value=${value:1}

      env["$key"]="$value"
  done < .env

  base_url="https://api.telegram.org/bot${env[BOT_TOKEN]}"
}

function get_bill_users() {
  local user_ids=$(cat data.json | jq '."'$1'"|values[].id')

  echo $user_ids
}

function check_all_bills() {
  local bills=$(cat data.json | jq 'keys[]' | sed 's/"//g')

  for bill in $bills; do
    barq_e_man_get_planned $bill
  done
}

function barq_e_man_get_current() {
  local today=$(python -c "import jdatetime; date=jdatetime.date.today(); print(date.strftime('%Y/%m/%d'))")

  local response=$(curl 'https://uiapi2.saapa.ir/api/ebills/BlackoutsReport' --compressed -X POST -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:137.0) Gecko/20100101 Firefox/137.0' -H 'Accept: application/json, text/plain, */*' -H 'Accept-Language: en-US,en;q=0.5' -H 'Accept-Encoding: gzip, deflate, br, zstd' -H 'Content-Type: application/json; charset=utf-8' -H 'Referer: https://bargheman.com/' -H 'Origin: https://bargheman.com' -H 'Sec-Fetch-Dest: empty' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: cross-site' -H 'Authorization: Bearer '${env[BARQ_TOKEN]} -H 'Connection: keep-alive' --data-raw '{"bill_id":"'$1'","date":"'$today'"}' 2>/dev/zero)

  local data=$(echo $response | jq ".data")
  # local data=$(cat jaari-response.json | jq ".[2].data")

  local data_length=$(echo $data | jq 'length')

  if [[ "$data_length" -le 1 ]]; then
    echo true
  fi
}

function barq_e_man_get_planned() {
  local today=$(python -c "import jdatetime; date=jdatetime.date.today(); print(date.strftime('%Y/%m/%d'))")
  local next_few_days=$(python -c "import jdatetime; date=jdatetime.date.today()+jdatetime.timedelta(days=7); print(date.strftime('%Y/%m/%d'))")

  local response=$(curl 'https://uiapi2.saapa.ir/api/ebills/PlannedBlackoutsReport' --compressed -X POST -H 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:137.0) Gecko/20100101 Firefox/137.0' -H 'Accept: application/json, text/plain, */*' -H 'Accept-Language: en-US,en;q=0.5' -H 'Content-Type: application/json; charset=utf-8' -H 'Referer: https://bargheman.com/' -H 'Origin: https://bargheman.com' -H 'Sec-Fetch-Dest: empty' -H 'Sec-Fetch-Mode: cors' -H 'Sec-Fetch-Site: cross-site' -H 'Authorization: Bearer '${env[BARQ_TOKEN]} -H 'Connection: keep-alive' --data-raw '{"bill_id":"'$1'","from_date":"'$today'","to_date":"'next_few_days'"}' 2>/dev/zero)

  local data=$(echo $response | jq ".data")
  # local data=$(cat planned-response.json | jq ".[2].data")

  local data_length=$(echo $data | jq 'length')

  local current=$(barq_e_man_get_current $1)

  if [[ "$data_length" -gt 0 ]] && [ ! -z $current ]; then
    for i in $(seq 0 1 $((data_length-1))); do
      local date=$(echo $data | jq '.['$i'].outage_date' | sed 's/"//g')
      local start_time=$(echo $data | jq '.['$i'].outage_start_time' | sed 's/"//g')
      local stop_time=$(echo $data | jq '.['$i'].outage_stop_time' | sed 's/"//g')

      # local user_ids=$(get_bill_users $1)
      local user_ids=$(check_last_sent $1 $date $start_time)

      for user_id in $user_ids; do
        send_barq_template_to_user $user_id $1 $date $start_time $stop_time
        update_data_set_last_sent_for_bill $1 $user_id $date $start_time

        echo "Send message to $user_id for $1 with params: $date - $start_time - $stop_time"
      done
    done
  fi
}

function create_webhook() {
  rm serveo.log
  while true; do
    echo "Connect to Serveo"
    ssh -R 80:localhost:${env[PORT]} serveo.net > serveo.log
    echo "Serveo connection faild"
  done
}

function make_webhook_persist() {
  while true; do
    local pid=$(ps $create_webhook_pid | awk 'NR==2 { print $1 }')

    if [[ $pid != $create_webhook_pid ]]; then
      if [ -n $create_webhook_pid ]; then
        kill $create_webhook_pid 2>/dev/zero
      fi

      create_webhook &
      create_webhook_pid=$!

      echo "Webhook address: $(get_webhook_address)"
      set_webhook $(get_webhook_address)
    fi

    sleep .1
  done

}

function get_webhook_address() {
  local address

  while [ -z $address ]; do
    sleep 0.01
    address=$(head -n 1 serveo.log| grep -Eo "https://[a-z0-9.]+")
  done


  echo $address
}

function webhook() {
  while true; do
    local input=$(cat response.json | netcat -lp ${env[PORT]} | awk -f response.awk)
    local sender_id=$(echo $input | jq '.message.from.id')
    local message_text=$(echo $input | jq '.message.text' | sed 's/"//g')
    # echo -e "\t\tuser = $sender_id"
    # echo -e "\t\tmessage = $message_text"
    local command=$(echo $message_text | awk '{print $1}')
    local parameters=$(echo $message_text | awk '{print $2}')

    case $command in
      /start)
        echo "User ($sender_id) started the conversation"
        send_message_to_user $sender_id "خوش آمدید"
      ;;

      /add)
        echo "Add user ($sender_id) to $parameters"
        update_data_add_user_to_bill $parameters $sender_id
        send_message_to_user $sender_id "قبض $parameters برای شما اضافه شد"
      ;;

      /remove)
        echo "Remove user ($sender_id) from $parameters"
        update_data_remove_user_from_bill $parameters $sender_id
        send_message_to_user $sender_id "قبض $parameters برای شما حذف شد"
      ;;

      /list)
        echo "List user ($sender_id) bills list"
        # TODO Send bills of user to it's chat
      ;;

      *)
        echo "Command '$message_text' not found"
        send_message_to_user $sender_id Message⠀is⠀not⠀valid
    esac
  done
}

function get_me() {
  local api_get_me="$base_url/getMe"

  if [ "${env[USE_PROXYCHAINS]}" == "true" ]; then
    proxychains curl $api_get_me \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      2>/dev/zero
  else
    curl $api_get_me \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      2>/dev/zero
  fi
}

function set_webhook() {
  local api_set_webhook="$base_url/setWebhook"
  # local webhook_url=$(get_webhook_address)

  if [ "${env[USE_PROXYCHAINS]}" == "true" ]; then
    proxychains curl $api_set_webhook \
      -X POST \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d '{"url":"'$1'"}' \
      2>/dev/zero 1>&2
  else
    curl $api_set_webhook \
      -X POST \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d '{"url":"'$1'"}' \
      2>/dev/zero 1>&2
  fi

  send_message_to_user 111156044 "Wehhook set to $webhook_url"
}

function send_message_to_user() {
  local api_send_message="$base_url/sendMessage"

  if [ "${env[USE_PROXYCHAINS]}" == "true" ]; then
    proxychains curl $api_send_message \
      -X POST \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d '{
          "chat_id":"'$1'",
          "text":"'${2/ /⠀}'"
        }' \
      2>/dev/zero 1>&2
  else
    curl $api_send_message \
      -X POST \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d '{
          "chat_id":"'$1'",
          "text":"'${2/ /⠀}'"
        }' \
      2>/dev/zero 1>&2
  fi
}

function send_barq_template_to_user() {
  local api_send_message="$base_url/sendMessage"

  if [ "${env[USE_PROXYCHAINS]}" == "true" ]; then
    proxychains curl $api_send_message \
      -X POST \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d '{
          "chat_id":"'$1'",
          "text":"برای قبض '$2' یک خاموشی در تاریخ '$3' از ساعت '$4' تا '$5' ثبت شده است"
        }' \
      2>/dev/zero 1>&2
  else
    curl $api_send_message \
      -X POST \
      -H 'Accept: application/json, text/plain, */*' \
      -H 'Accept-Language: en-US,en;q=0.5' \
      -H 'Accept-Encoding: gzip, deflate, br, zstd' \
      -H 'Content-Type: application/json; charset=utf-8' \
      -d '{
          "chat_id":"'$1'",
          "text":"برای قبض '$2' یک خاموشی در تاریخ '$3' از ساعت '$4' تا '$5' ثبت شده است"
        }' \
      2>/dev/zero 1>&2
  fi
}

function update_data_add_user_to_bill() {
  if [[ -n $1 && -n $2 ]]; then
    local bill_exists=$(cat data.json | jq '."'$1'"' | grep '^null$')
    if [[ -z $bill_exists ]]; then
      local user_exists=$(cat data.json | jq '."'$1'"|values[].id' | grep -o "\b$2\b")

      if [[ -z $user_exists ]]; then
        local data=$(cat data.json | jq '(."'$1'"|values)|=.+[{id:'$2',last_sent:false}]')
        
        echo $data > data.json
      fi
    else
      local data=$(cat data.json | jq '.=.+{"'$1'":[{id:'$2',last_sent:false}]}')
      
      echo $data > data.json
    fi
  fi
}

function update_data_remove_user_from_bill() {
  if [[ -n $1 && -n $2 ]]; then
    local bill_exists=$(cat data.json | jq '."'$1'"' | grep '^null$')
    if [[ -z $bill_exists ]]; then
      local user_exists=$(cat data.json | jq '."'$1'"|values[].id' | grep -o "\b$2\b")

      if [[ -n $user_exists ]]; then
        local data=$(cat data.json | jq '(."'$1'"|values)|=.-[{id:'$2',last_sent:false}]')
        
        echo $data > data.json
      fi
    fi
  fi
}

function update_data_set_last_sent_for_bill() {
  if [[ -n $1 && -n $2 && -n $3 && -n $4 ]]; then
    local data=$(cat data.json | jq '(."'$1'"|values[]|select(.id=='$2').last_sent)|={"date":"'$3'","time":"'$4'"}')

    echo $data > data.json
  fi
}

function check_last_sent() {
  if [[ -n $1 && -n $2 && -n $3 ]]; then
    local data=$(cat data.json | jq '."'$1'"|values[]|select (.last_sent==false or .last_sent.date<"'$2'" or (.last_sent.date=="'$2'" and .last_sent.time<"'$3'")) | .id')

    echo $data
  fi
}

if [ "$1" = "install" ]; then
  sudo systemctl stop bot.service
  sudo systemctl disable bot.service
  sudo rm /lib/systemd/system/bot.service

  echo "
    [Unit]
    Description=Telegram Bot - Barq-e Man: Khaamushi
    After=network-online.target

    [Service]
    ExecStart=/bin/bash $PWD/bot.sh
    WorkingDirectory=$PWD
    StandardOutput=inherit
    StandardError=inherit
    Restart=always
    User=$USER

    [Install]
    WantedBy=multi-user.target" > bot.service

    sudo mv bot.service /lib/systemd/system/
    sudo systemctl start bot.service
    sudo systemctl enable bot.service
else
  if [ ! -f data.json ]; then
    echo '{}' > data.json
  fi

  set_variables

  if [ "${env[USE_PROXYCHAINS]}" == "true" ]; then
    while [[ -z $proxy_connected ]]; do
      echo "Testing proxy connection"
      proxy_connected=$(proxychains curl https://google.com 2>/dev/zero 1>&2 && echo true)
      sleep .05
    done
    echo 'Proxy connected'
  fi

  if [ -z ${env[BOT_WEBHOOK_URL]} ]; then
    make_webhook_persist &
    make_webhook_persist_pid=$!
  else
    set_webhook ${env[BOT_WEBHOOK_URL]}
    echo "Webhook address: ${env[BOT_WEBHOOK_URL]}"
  fi


  # create_webhook &
  # create_webhook_pid=$!

  # echo "Webhook address: $(get_webhook_address)"
  # set_webhook

  webhook &
  webhook_pid=$!

  while true; do
    echo "Check bills"
    check_all_bills
    sleep 1800
  done

  wait $webhook_pid
  kill $webhook_pid

  #wait $make_webhook_persist_pid
  kill $make_webhook_persist_pid

  #wait $create_webhook_pid
  # kill $create_webhook_pid
fi
