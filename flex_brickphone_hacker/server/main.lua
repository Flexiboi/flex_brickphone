CreateThread(function()
    Citizen.Wait(1000)
    local contactRegistered = exports.flex_brickphone:registerContact(
        'hacker_man',
        {
            id = 'hacker_man',
            name = locale("phone_message.messages.contect_name"),
            number = '0101010444',
            enabled = true,
            target = 'all'
        }
    )
end)