-- Simple GPS tower broadcaster
-- Opens modem on channel 0
peripheral.find("modem", function(name, p) p.open(0) end)
print("GPS tower active")
while true do
    os.pullEvent("modem_message") -- keep tower online
end
