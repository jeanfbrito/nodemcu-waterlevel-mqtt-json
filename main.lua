-- Your access point's SSID and password
local SSID = "greenhouse"
local SSID_PASSWORD = "senhasupersecreta"
local DEVICE = "undefined"
local timesRunned = 0
local HOST = "192.168.13.91"

-- configure ESP as a station
wifi.setmode(wifi.STATION)
wifi.sta.config(SSID,SSID_PASSWORD)
wifi.sta.autoconnect(1)
DEVICE = string.gsub(wifi.sta.getmac(), ":", "")

gpio.mode(5, gpio.INPUT,gpio.PULLUP)
gpio.mode(6, gpio.INPUT,gpio.PULLUP)

mqtt = mqtt.Client(DEVICE, 120, "", "")

-- setup Last Will and Testament (optional)
-- Broker will publish a message with qos = 0, retain = 0, data = "offline"
-- to topic "/lwt" if client don't send keepalive packet
mqtt:lwt("devices/" .. DEVICE .. "/status", "offline", 0, 1)

---mqtt:on("connect", function(con)
--    print ("connected")
--    mqtt:publish("devices/" .. DEVICE .. "/status","online",0,1, function(conn)
--        print("sent online status for LWT use")
--      end)
--  end)

mqtt:on("offline", function(con)
    print ("offline, Reconnecting")
    mqtt:connect(HOST, 1883, 0, function(conn)
        print("reconnected to broker")
        mqtt:publish("devices/" .. DEVICE .. "/status","online",0,1, function(conn)
            print("sent online status for LWT use")
          end)
        sync_rtc()
      end)
  end)

mqtt:on("message", function(conn, topic, data)
    print("Recieved:" .. topic .. " : " .. data)
    if (topic=="hub/1hz") then
      print("timestamp: " .. data)
      rtctime.set(data/1000,0)
      mqtt:unsubscribe("hub/1hz", function(conn) print("unsubscribe 1hz success") end)
    end
  end)

function check_wifi()
  local ip = wifi.sta.getip()
  if(ip==nil) then
    print("Connecting...")
  else
    tmr.stop(0)
    print("Connected to AP!")
    print(ip)
    mqtt:connect(HOST, 1883, 0, function(conn)
        print("Connected to broker")
        mqtt:publish("devices/" .. DEVICE .. "/status","online",0,1, function(conn)
            print("sent online status for LWT use")
          end)
        sync_rtc()
      end)
    tmr.alarm(1,10000,1,sendData)
  end
end

function sync_rtc()
  mqtt:subscribe("hub/1hz",0, function(conn) print("subscribe 1hz success") end)
end

function sendData()
  --local t, h = getTempHumi()
  local highLevelSwitch = gpio.read(5)
  local lowLevelSwitch = gpio.read(6)
  local waterlevel = adc.read(0)
  local n = node.heap()
  local times = timesRunned
  local time = rtctime.get()
  timesRunned = timesRunned + 1
  dataString = '{"device":"'.. DEVICE ..'","timestamp":'.. time ..',"level":' .. waterlevel .. ',"highlevel":' .. highLevelSwitch .. ',"lowLevel":' .. lowLevelSwitch .. ',"runned":' .. times .. ',"heap":' .. n .. '}'
  mqtt:publish("sensors/" .. DEVICE .. "/measurement",dataString,0,0, function(conn)
      print("sent: ".. dataString)
    end)

end

function getTempHumi()
  pin = 4
  local status,temp,humi,temp_decimial,humi_decimial = dht.read(pin)
  if( status == dht.OK ) then
    -- Float firmware using this example
    --print("DHT Temperature:"..temp..";".."Humidity:"..humi)
  elseif( status == dht.ERROR_CHECKSUM ) then
    --print( "DHT Checksum error." );
  elseif( status == dht.ERROR_TIMEOUT ) then
    --print( "DHT Time out." );
  end
  return temp, humi
end

tmr.alarm(0,2000,1,check_wifi)

--set timer to subscribe to hub heartbeat to update the RTC
tmr.alarm(2,600000,1,function()
    sync_rtc()
  end)
