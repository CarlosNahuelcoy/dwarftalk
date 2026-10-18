-- Make sibling DwarfTalk modules require()-able no matter which script runs first
do
    local dir = debug.getinfo(1, 'S').source:match('^@(.+)[/\\][^/\\]+$')
    if dir and not package.path:find(dir .. '/?.lua', 1, true) then
        package.path = package.path .. ';' .. dir .. '/?.lua'
    end
end
-- Show next pending notification
local notification = require('notification_popup')
notification.show_notification()