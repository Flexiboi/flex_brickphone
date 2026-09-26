local GROUP_PREFIX = 'group:'
local groupCache = {}
local groupInvites = {}
local groupHandlers = {}
local groupCreateLocks = {}
local emitHook

local function groupDebug(message, ...)
    if Config.Debug then
        print(('[flex_brickphone][groups] ' .. message):format(...))
    end
end

local function sendGroupSystemMessage(src, text, contactId)
    if not src or not GetPlayerName(src) then
        groupDebug('Cannot send system message: invalid player %s', tostring(src))
        return false
    end

    contactId = contactId or 'groups'
    text = tostring(text or '')
    groupDebug('Sending system message to player %s, contact=%s: %s', tostring(src), contactId, text)

    if SendBrickPhoneMessage then
        local ok = SendBrickPhoneMessage(src, contactId, text, 'contact')
        groupDebug('SendBrickPhoneMessage returned %s', tostring(ok))
        return ok
    end

    TriggerClientEvent('flex_brickphone:client:appendMessage', src, contactId, {
        from = 'contact',
        senderName = 'Groups',
        text = text
    })
    return true
end

local function groupContactId(groupId)
    return GROUP_PREFIX .. tostring(groupId)
end

local function groupIdFromContact(contactId)
    if type(contactId) ~= 'string' or contactId:sub(1, #GROUP_PREFIX) ~= GROUP_PREFIX then return nil end
    return tonumber(contactId:sub(#GROUP_PREFIX + 1))
end

local function getIdentifier(src)
    local player = GetPlayer(src)
    if not player or not player.PlayerData then return nil end

    local citizenid = player.PlayerData.citizenid
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end

    return citizenid
end

local function playerName(src)
    return GetPlayerName(src) or ('Player %s'):format(src)
end

local function dbGroup(groupId)
    return MySQL.single.await('SELECT * FROM flex_brickphone_groups WHERE id = ?', { groupId })
end

local function ownedGroupId(identifier)
    if not identifier then return nil end

    return MySQL.scalar.await([[
        SELECT id
        FROM flex_brickphone_groups
        WHERE owner_identifier = ? AND status = 'active'
        ORDER BY id ASC
        LIMIT 1
    ]], { identifier })
end

local function createPersistentGroup(src, name, avatar)
    local identifier = getIdentifier(src)
    if not identifier or type(name) ~= 'string' or name == '' or #name > Config.Groups.maxNameLength then
        return false, 'invalid'
    end

    if groupCreateLocks[identifier] then
        return false, 'busy'
    end

    groupCreateLocks[identifier] = true

    local function unlock()
        groupCreateLocks[identifier] = nil
    end

    local existingGroupId = ownedGroupId(identifier)
    if existingGroupId then
        unlock()
        return false, 'already_leader', existingGroupId
    end

    local ownerName = playerName(src)
    local okGroup, groupId = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO flex_brickphone_groups (name, owner_identifier, owner_name, avatar) VALUES (?, ?, ?, ?)',
            { name:sub(1, Config.Groups.maxNameLength), identifier, ownerName, avatar }
        )
    end)

    if not okGroup or not groupId then
        unlock()
        return false, 'create_failed'
    end

    local okMember, memberId = pcall(function()
        return MySQL.insert.await(
            'INSERT INTO flex_brickphone_group_members (group_id, identifier, name, role) VALUES (?, ?, ?, ?)',
            { groupId, identifier, ownerName, 'owner' }
        )
    end)

    if not okMember or not memberId then
        pcall(function()
            MySQL.update.await('DELETE FROM flex_brickphone_groups WHERE id = ?', { groupId })
        end)
        unlock()
        return false, 'create_failed'
    end

    unlock()

    emitHook('groupCreated', groupId, src, name)
    RefreshBrickPhoneContacts(src)
    return groupId
end

local function isMember(groupId, identifier)
    return MySQL.scalar.await(
        'SELECT 1 FROM flex_brickphone_group_members WHERE group_id = ? AND identifier = ? LIMIT 1',
        { groupId, identifier }
    ) ~= nil
end

local function memberRole(groupId, identifier)
    return MySQL.scalar.await(
        'SELECT role FROM flex_brickphone_group_members WHERE group_id = ? AND identifier = ? LIMIT 1',
        { groupId, identifier }
    )
end

local function canManage(groupId, identifier)
    local role = memberRole(groupId, identifier)
    return role == 'owner' or role == 'admin'
end

emitHook = function(name, ...)
    TriggerEvent(('flex_brickphone:%s'):format(name), ...)
    local handler = groupHandlers[name]
    if handler then
        local ok, err = pcall(handler, ...)
        if not ok then
            print(('[flex_brickphone] group hook %s failed: %s'):format(name, err))
        end
    end
end

MySQL.ready(function()
    groupDebug('MySQL is ready; initializing group tables')
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `flex_brickphone_groups` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(100) NOT NULL,
            `owner_identifier` VARCHAR(128) NOT NULL,
            `owner_name` VARCHAR(100) NOT NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'active',
            `avatar` VARCHAR(255) NULL DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_owner` (`owner_identifier`),
            INDEX `idx_status` (`status`)
        );
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `flex_brickphone_group_members` (
            `group_id` BIGINT UNSIGNED NOT NULL,
            `identifier` VARCHAR(128) NOT NULL,
            `name` VARCHAR(100) NOT NULL,
            `role` VARCHAR(20) NOT NULL DEFAULT 'member',
            `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`group_id`, `identifier`),
            INDEX `idx_identifier` (`identifier`)
        );
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `flex_brickphone_group_messages` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `group_id` BIGINT UNSIGNED NOT NULL,
            `sender_identifier` VARCHAR(128) NOT NULL,
            `sender_name` VARCHAR(100) NOT NULL,
            `message_type` VARCHAR(30) NOT NULL DEFAULT 'text',
            `message` TEXT NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_group_message` (`group_id`, `id`)
        );
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `flex_brickphone_group_invites` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `group_id` BIGINT UNSIGNED NOT NULL,
            `target_identifier` VARCHAR(128) NOT NULL,
            `inviter_identifier` VARCHAR(128) NOT NULL,
            `inviter_name` VARCHAR(100) NOT NULL,
            `expires_at` DATETIME NOT NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_group_invite` (`group_id`, `target_identifier`),
            INDEX `idx_invite_target` (`target_identifier`, `status`)
        );
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `flex_brickphone_group_contacts` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `group_id` BIGINT UNSIGNED NOT NULL,
            `contact_id` VARCHAR(100) NOT NULL,
            `display_name` VARCHAR(100) NOT NULL,
            `contact_type` VARCHAR(50) NOT NULL DEFAULT 'contact',
            `phone_identifier` VARCHAR(100) NULL DEFAULT NULL,
            `permissions` VARCHAR(1000) NULL DEFAULT NULL,
            `created_by` VARCHAR(128) NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uq_group_contact` (`group_id`, `contact_id`)
        );
    ]])
end)

local function notifyGroup(groupId, message, exclude)
    local rows = MySQL.query.await(
        'SELECT identifier FROM flex_brickphone_group_members WHERE group_id = ?',
        { groupId }
    )
    for _, row in ipairs(rows or {}) do
        local target = GetPlayerFromIdentifier and GetPlayerFromIdentifier(row.identifier) or nil
        if not target then
            for _, player in ipairs(GetPlayers()) do
                if getIdentifier(tonumber(player)) == row.identifier then target = tonumber(player) break end
            end
        end
        if target and target ~= exclude then
            sendGroupSystemMessage(target, message, groupContactId(groupId))
        end
    end
end

local function groupContactFor(groupId)
    local group = dbGroup(groupId)
    if not group or group.status ~= 'active' then return nil end
    return {
        id = groupContactId(groupId),
        groupId = groupId,
        name = group.name,
        number = ('GROUP-%s'):format(groupId),
        isGroup = true,
        avatar = group.avatar,
        role = memberRole(groupId, getIdentifier(source))
    }
end

local function findOnlineByIdentifier(identifier)
    for _, player in ipairs(GetPlayers()) do
        local src = tonumber(player)
        if getIdentifier(src) == identifier then return src end
    end
end

local function loadGroupsForPlayer(src)
    local identifier = getIdentifier(src)
    if not identifier then return {} end

    local rows = MySQL.query.await([[
        SELECT g.id, g.name, g.avatar, m.role
        FROM flex_brickphone_groups g
        INNER JOIN flex_brickphone_group_members m ON m.group_id = g.id
        WHERE m.identifier = ? AND g.status = 'active'
        ORDER BY g.name ASC
    ]], { identifier })

    local groups = {}
    for _, row in ipairs(rows or {}) do
        groups[groupContactId(row.id)] = {
            id = groupContactId(row.id),
            groupId = row.id,
            name = row.name,
            number = ('GROUP-%s'):format(row.id),
            isGroup = true,
            avatar = row.avatar,
            role = row.role
        }
    end
    return groups
end

local function groupMessages(src, groupId)
    local identifier = getIdentifier(src)
    if not identifier or not isMember(groupId, identifier) then return nil end

    local rows = MySQL.query.await([[
        SELECT id, sender_identifier, sender_name, message_type, message, created_at
        FROM flex_brickphone_group_messages
        WHERE group_id = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { groupId, Config.MessageHistoryLimit })

    local messages = {}
    for i = #rows, 1, -1 do
        local row = rows[i]
        messages[#messages + 1] = {
            id = row.id,
            from = row.sender_identifier == identifier and 'player' or 'contact',
            senderName = row.sender_name,
            text = row.message,
            messageType = row.message_type,
            timestamp = row.created_at
        }
    end
    return messages
end

local function sendGroupMessage(groupId, src, message, messageType)
    groupId = tonumber(groupId)
    if not groupId or type(message) ~= 'string' or #message > 4000 then return false, 'invalid' end

    local identifier = getIdentifier(src)
    if not identifier or not isMember(groupId, identifier) then return false, 'not_member' end

    local group = dbGroup(groupId)
    if not group or group.status ~= 'active' then return false, 'invalid_group' end

    local senderName = playerName(src)
    local result = MySQL.insert.await([[
        INSERT INTO flex_brickphone_group_messages
            (group_id, sender_identifier, sender_name, message_type, message)
        VALUES (?, ?, ?, ?, ?)
    ]], { groupId, identifier, senderName, messageType or 'text', message })

    local members = MySQL.query.await(
        'SELECT identifier FROM flex_brickphone_group_members WHERE group_id = ?',
        { groupId }
    )

    for _, member in ipairs(members or {}) do
        local target = findOnlineByIdentifier(member.identifier)
        if target then
            local payload = {
                id = result,
                from = member.identifier == identifier and 'player' or 'contact',
                senderName = senderName,
                text = message,
                messageType = messageType or 'text'
            }
            if target ~= src then
                TriggerClientEvent('flex_brickphone:client:appendMessage', target, groupContactId(groupId), payload)
            end
            emitHook('groupMessageReceived', groupId, target, src, payload)
        end
    end

    emitHook('groupMessageSent', groupId, src, message)
    return true, result
end

local function normalizeCommand(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' '):lower()
end

local function groupCommand(src, message)
    local raw = tostring(message or '')
    local normalized = normalizeCommand(raw)
    local words = {}
    for word in raw:gmatch('%S+') do words[#words + 1] = word end

    local commands = {
        create = normalizeCommand(locale('groups.commands.create')),
        list = normalizeCommand(locale('groups.commands.list')),
        invite = normalizeCommand(locale('groups.commands.invite')),
        accept = normalizeCommand(locale('groups.commands.accept')),
        decline = normalizeCommand(locale('groups.commands.decline')),
        leave = normalizeCommand(locale('groups.commands.leave')),
        remove = normalizeCommand(locale('groups.commands.remove')),
        disband = normalizeCommand(locale('groups.commands.disband')),
        contacts = normalizeCommand(locale('groups.commands.contacts')),
        addcontact = normalizeCommand(locale('groups.commands.addcontact')),
        removecontact = normalizeCommand(locale('groups.commands.removecontact')),
        renamecontact = normalizeCommand(locale('groups.commands.renamecontact')),
        rename = normalizeCommand(locale('groups.commands.rename')),
        members = normalizeCommand(locale('groups.commands.members')),
        help = normalizeCommand(locale('groups.commands.help'))
    }

    local englishCommands = {
        create = 'create', list = 'list', invite = 'invite', accept = 'accept',
        decline = 'decline', leave = 'leave', remove = 'remove', disband = 'disband',
        contacts = 'contacts', addcontact = 'addcontact', removecontact = 'removecontact',
        renamecontact = 'renamecontact', rename = 'rename', members = 'members', help = 'help'
    }

    local function reply(key, ...)
        local text = locale(key)
        if select('#', ...) > 0 then text = text:format(...) end
        sendGroupSystemMessage(src, text)
        return true
    end

    if normalized == '' then
        return reply('groups.help_message')
    end

    local command = normalizeCommand(words[1])
    local commandKey

    for key, translated in pairs(commands) do
        if command == translated or command == englishCommands[key] then
            commandKey = key
            break
        end
    end

    groupDebug('Command received from %s: raw=%q normalized=%q resolved=%s', tostring(src), raw, command, tostring(commandKey))

    if not commandKey then
        groupDebug('Unknown group command from %s: %q', tostring(src), command)
        return reply('groups.unknown_command')
    end

    if commandKey == 'help' then
        return reply('groups.help_message')
    end

    if commandKey == 'create' then
        local name = table.concat(words, ' ', 2):sub(1, Config.Groups.maxNameLength)
        if name == '' then return reply('groups.create_usage') end

        local groupId, errorCode, existingGroupId = createPersistentGroup(src, name)
        if not groupId then
            if errorCode == 'already_leader' then
                groupDebug(
                    'Create blocked: src=%s already owns active group %s',
                    tostring(src),
                    tostring(existingGroupId)
                )
                return reply('groups.already_leader', existingGroupId)
            end

            if errorCode == 'busy' then
                return reply('groups.create_failed')
            end

            return reply('groups.create_failed')
        end

        groupDebug('Group created: src=%s groupId=%s name=%q', tostring(src), tostring(groupId), name)
        return reply('groups.created', name)
    end

    if commandKey == 'list' then
        local groups = loadGroupsForPlayer(src)
        local lines = { locale('groups.list_title'), '' }
        local count = 0
        for _, group in pairs(groups) do
            count = count + 1
            lines[#lines + 1] = ('- **%s** — `%s`'):format(group.name, group.groupId)
        end
        if count == 0 then lines[#lines + 1] = locale('groups.no_groups') end
        sendGroupSystemMessage(src, table.concat(lines, '\n'))
        return true
    end

    local identifier = getIdentifier(src)
    local targetGroup = tonumber(words[2])

    if commandKey == 'members' then
        if not targetGroup or not identifier or not isMember(targetGroup, identifier) then return reply('groups.not_member') end
        local group = dbGroup(targetGroup)
        if not group or group.status ~= 'active' then return reply('groups.invalid_group') end

        local rows = MySQL.query.await(
            'SELECT name, role FROM flex_brickphone_group_members WHERE group_id = ? ORDER BY CASE WHEN role = "owner" THEN 0 WHEN role = "admin" THEN 1 ELSE 2 END, joined_at ASC',
            { targetGroup }
        )

        local lines = { locale('groups.members_title'):format(group.name), '' }
        if #rows == 0 then
            lines[#lines + 1] = locale('groups.no_members')
        else
            for _, row in ipairs(rows) do
                lines[#lines + 1] = ('- **%s** — `%s`'):format(row.name, row.role)
            end
        end

        sendGroupSystemMessage(src, table.concat(lines, '\n'))
        return true
    end

    if commandKey == 'rename' then
        if not targetGroup or not identifier or not canManage(targetGroup, identifier) then return reply('groups.permission_denied') end
        local newName = table.concat(words, ' ', 3):sub(1, Config.Groups.maxNameLength)
        if newName == '' then return reply('groups.rename_usage') end

        local group = dbGroup(targetGroup)
        if not group or group.status ~= 'active' then return reply('groups.invalid_group') end

        local updated = MySQL.update.await(
            'UPDATE flex_brickphone_groups SET name = ? WHERE id = ? AND status = "active"',
            { newName, targetGroup }
        )
        if updated == nil then return reply('groups.rename_failed') end

        emitHook('groupRenamed', targetGroup, src, newName)
        notifyGroup(targetGroup, locale('groups.renamed_notice'):format(newName))
        RefreshBrickPhoneContacts(src)
        return reply('groups.renamed', newName)
    end

    if commandKey == 'invite' then
        if not targetGroup or not canManage(targetGroup, identifier) then return reply('groups.permission_denied') end
        local memberCount = MySQL.scalar.await('SELECT COUNT(*) FROM flex_brickphone_group_members WHERE group_id = ?', { targetGroup }) or 0
        if tonumber(memberCount) >= Config.Groups.maxMembers then return reply('groups.max_members') end
        local targetSrc = tonumber(words[3])
        if not targetSrc or not GetPlayerName(targetSrc) or targetSrc == src then return reply('groups.invalid_player') end
        local targetIdentifier = getIdentifier(targetSrc)
        if not targetIdentifier then return reply('groups.invalid_player') end
        if isMember(targetGroup, targetIdentifier) then return reply('groups.already_member') end
        local existing = MySQL.scalar.await(
            'SELECT id FROM flex_brickphone_group_invites WHERE group_id = ? AND target_identifier = ? AND status = ? AND expires_at > NOW()',
            { targetGroup, targetIdentifier, 'pending' }
        )
        if existing then return reply('groups.invite_exists') end
        local group = dbGroup(targetGroup)
        if not group or group.status ~= 'active' then return reply('groups.invalid_group') end
        local inviteId = MySQL.insert.await([[
            INSERT INTO flex_brickphone_group_invites
                (group_id, target_identifier, inviter_identifier, inviter_name, expires_at)
            VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))
        ]], { targetGroup, targetIdentifier, identifier, playerName(src), Config.Groups.inviteExpiry })
        if not inviteId then return reply('groups.invite_failed') end
        emitHook('groupInviteSent', targetGroup, src, targetSrc, inviteId)
        sendGroupSystemMessage(targetSrc, locale('groups.invite_received'):format(playerName(src), group.name, targetGroup))
        return reply('groups.invite_sent')
    end

    if commandKey == 'accept' or commandKey == 'decline' then
        if not targetGroup then return reply('groups.invite_usage') end
        local invite = MySQL.single.await([[
            SELECT * FROM flex_brickphone_group_invites
            WHERE group_id = ? AND target_identifier = ? AND status = 'pending' AND expires_at > NOW()
            LIMIT 1
        ]], { targetGroup, identifier })
        if not invite then return reply('groups.invite_not_found') end

        if commandKey == 'decline' then
            MySQL.update.await('UPDATE flex_brickphone_group_invites SET status = ? WHERE id = ?', { 'declined', invite.id })
            emitHook('groupInviteDeclined', targetGroup, src, invite.inviter_identifier, invite.id)
            local inviterSrc = findOnlineByIdentifier(invite.inviter_identifier)
            if inviterSrc then sendGroupSystemMessage(inviterSrc, locale('groups.invite_declined_notice'):format(playerName(src))) end
            return reply('groups.invite_declined')
        end

        if isMember(targetGroup, identifier) then
            MySQL.update.await('UPDATE flex_brickphone_group_invites SET status = ? WHERE id = ?', { 'accepted', invite.id })
            return reply('groups.already_member')
        end

        local count = MySQL.scalar.await('SELECT COUNT(*) FROM flex_brickphone_group_members WHERE group_id = ?', { targetGroup }) or 0
        if tonumber(count) >= Config.Groups.maxMembers then return reply('groups.max_members') end

        MySQL.insert.await(
            'INSERT INTO flex_brickphone_group_members (group_id, identifier, name, role) VALUES (?, ?, ?, ?)',
            { targetGroup, identifier, playerName(src), 'member' }
        )
        MySQL.update.await('UPDATE flex_brickphone_group_invites SET status = ? WHERE id = ?', { 'accepted', invite.id })
        emitHook('groupInviteAccepted', targetGroup, src, invite.inviter_identifier, invite.id)
        emitHook('groupMemberAdded', targetGroup, invite.inviter_identifier, src)
        notifyGroup(targetGroup, locale('groups.member_joined'):format(playerName(src)), src)
        RefreshBrickPhoneContacts(src)
        return reply('groups.joined', dbGroup(targetGroup).name)
    end

    if commandKey == 'leave' then
        if not targetGroup then return reply('groups.leave_usage') end
        if not isMember(targetGroup, identifier) then return reply('groups.not_member') end
        local group = dbGroup(targetGroup)
        local role = memberRole(targetGroup, identifier)
        MySQL.update.await('DELETE FROM flex_brickphone_group_members WHERE group_id = ? AND identifier = ?', { targetGroup, identifier })
        emitHook('groupMemberLeft', targetGroup, src)
        notifyGroup(targetGroup, locale('groups.member_left'):format(playerName(src)), src)

        local remaining = MySQL.query.await('SELECT identifier, role FROM flex_brickphone_group_members WHERE group_id = ? ORDER BY CASE WHEN role = "admin" THEN 0 ELSE 1 END, joined_at ASC', { targetGroup })
        if #remaining == 0 then
            if Config.Groups.deleteEmptyGroups then
                MySQL.update.await('UPDATE flex_brickphone_groups SET status = "deleted" WHERE id = ?', { targetGroup })
                MySQL.update.await('DELETE FROM flex_brickphone_group_contacts WHERE group_id = ?', { targetGroup })
                MySQL.update.await('DELETE FROM flex_brickphone_group_invites WHERE group_id = ?', { targetGroup })
                emitHook('groupDeleted', targetGroup, src)
            else
                groupDebug('Group %s is now empty; keeping it active', tostring(targetGroup))
            end
        elseif role == 'owner' and Config.Groups.transferOwnerOnLeave then
            local nextOwner

            for _, candidate in ipairs(remaining) do
                if not ownedGroupId(candidate.identifier) then
                    nextOwner = candidate
                    break
                end
            end

            if nextOwner then
                MySQL.update.await('UPDATE flex_brickphone_group_members SET role = "admin" WHERE group_id = ? AND role = "owner"', { targetGroup })
                MySQL.update.await('UPDATE flex_brickphone_group_members SET role = "owner" WHERE group_id = ? AND identifier = ?', { targetGroup, nextOwner.identifier })
                MySQL.update.await('UPDATE flex_brickphone_groups SET owner_identifier = ? WHERE id = ?', { nextOwner.identifier, targetGroup })
                emitHook('groupOwnerChanged', targetGroup, nextOwner.identifier)
                notifyGroup(targetGroup, locale('groups.ownership_changed'))
            else
                groupDebug(
                    'No eligible owner found for group %s after owner left; all remaining members already lead another active group',
                    tostring(targetGroup)
                )
            end
        end
        RefreshBrickPhoneContacts(src)
        return reply('groups.left', group and group.name or '')
    end

    if commandKey == 'remove' then
        if not targetGroup or not canManage(targetGroup, identifier) then return reply('groups.permission_denied') end
        local targetSrc = tonumber(words[3])
        if not targetSrc or not GetPlayerName(targetSrc) then return reply('groups.invalid_player') end
        local targetIdentifier = getIdentifier(targetSrc)
        if not targetIdentifier or targetIdentifier == identifier or not isMember(targetGroup, targetIdentifier) then return reply('groups.not_member') end
        local group = dbGroup(targetGroup)
        MySQL.update.await('DELETE FROM flex_brickphone_group_members WHERE group_id = ? AND identifier = ?', { targetGroup, targetIdentifier })
        emitHook('groupMemberRemoved', targetGroup, src, targetSrc)
        sendGroupSystemMessage(targetSrc, locale('groups.member_removed'):format(group and group.name or ''))
        notifyGroup(targetGroup, locale('groups.member_removed_notice'):format(playerName(targetSrc)), src)
        RefreshBrickPhoneContacts(targetSrc)
        return reply('groups.member_removed_by_you', playerName(targetSrc))
    end

    if commandKey == 'disband' then
        if not targetGroup or not identifier or memberRole(targetGroup, identifier) ~= 'owner' then return reply('groups.permission_denied') end
        local group = dbGroup(targetGroup)
        if not group or group.status ~= 'active' then return reply('groups.invalid_group') end
        notifyGroup(targetGroup, locale('groups.disbanded'):format(group.name))
        MySQL.update.await('UPDATE flex_brickphone_groups SET status = "deleted" WHERE id = ?', { targetGroup })
        MySQL.update.await('DELETE FROM flex_brickphone_group_members WHERE group_id = ?', { targetGroup })
        MySQL.update.await('DELETE FROM flex_brickphone_group_contacts WHERE group_id = ?', { targetGroup })
        MySQL.update.await('DELETE FROM flex_brickphone_group_invites WHERE group_id = ?', { targetGroup })
        emitHook('groupDeleted', targetGroup, src)
        RefreshBrickPhoneContacts(src)
        return reply('groups.disband_success', group.name)
    end

    if commandKey == 'contacts' and targetGroup then
        if not isMember(targetGroup, identifier) then return reply('groups.not_member') end
        local rows = MySQL.query.await('SELECT contact_id, display_name, contact_type FROM flex_brickphone_group_contacts WHERE group_id = ? ORDER BY display_name ASC', { targetGroup })
        local lines = { locale('groups.contacts_title'), '' }
        if #rows == 0 then lines[#lines + 1] = locale('groups.no_contacts') end
        for _, contact in ipairs(rows) do
            lines[#lines + 1] = ('- **%s** — `%s` (%s)'):format(contact.display_name, contact.contact_id, contact.contact_type)
        end
        sendGroupSystemMessage(src, table.concat(lines, '\n'))
        return true
    end

    return reply('groups.unknown_command')
end

local function HandleBrickPhoneGroupsMessage(src, data)
    if type(data) ~= 'table' or type(data.message) ~= 'string' then
        groupDebug('Invalid groups handler payload from %s', tostring(src))
        return false
    end

    groupDebug('Groups handler reached: src=%s message=%q', tostring(src), data.message)
    return groupCommand(src, data.message)
end

local registered = RegisterBrickPhoneContactHandler('groups', HandleBrickPhoneGroupsMessage)
print(('[flex_brickphone][groups] groups contact handler registered: %s'):format(tostring(registered)))

RegisterNetEvent('flex_brickphone:server:getGroupMessages', function(groupId)
    local src = source
    local messages = groupMessages(src, tonumber(groupId))
    if messages then TriggerClientEvent('flex_brickphone:client:receiveMessages', src, groupContactId(groupId), messages) end
end)

lib.callback.register('flex_brickphone:server:sendGroupMessage', function(src, groupId, message, messageType)
    return sendGroupMessage(groupId, src, message, messageType)
end)

exports('CreateGroup', function(src, name, avatar)
    local groupId = createPersistentGroup(src, name, avatar)
    return groupId or false
end)

exports('DeleteGroup', function(groupId, src)
    local identifier = getIdentifier(src)
    if not identifier or memberRole(groupId, identifier) ~= 'owner' then return false end
    MySQL.update.await('UPDATE flex_brickphone_groups SET status = "deleted" WHERE id = ?', { groupId })
    MySQL.update.await('DELETE FROM flex_brickphone_group_members WHERE group_id = ?', { groupId })
    MySQL.update.await('DELETE FROM flex_brickphone_group_contacts WHERE group_id = ?', { groupId })
    MySQL.update.await('DELETE FROM flex_brickphone_group_invites WHERE group_id = ?', { groupId })
    emitHook('groupDeleted', groupId, src)
    return true
end)

exports('GetGroup', function(groupId)
    return dbGroup(groupId)
end)

exports('GetGroups', function(src)
    return loadGroupsForPlayer(src)
end)

exports('GetAdminGroupId', function(src)
    local identifier = getIdentifier(src)
    if not identifier then return nil end

    return MySQL.scalar.await([[
        SELECT group_id
        FROM flex_brickphone_group_members gm
        INNER JOIN flex_brickphone_groups g ON g.id = gm.group_id
        WHERE gm.identifier = ?
          AND gm.role IN ('owner', 'admin')
          AND g.status = 'active'
        ORDER BY CASE WHEN gm.role = 'owner' THEN 0 ELSE 1 END, gm.group_id ASC
        LIMIT 1
    ]], { identifier })
end)

exports('AddGroupMember', function(groupId, src, targetSrc, role)
    local identifier = getIdentifier(src)
    local targetIdentifier = getIdentifier(targetSrc)
    if not identifier or not targetIdentifier or not canManage(groupId, identifier) then return false end
    if isMember(groupId, targetIdentifier) then return false end
    MySQL.insert.await(
        'INSERT INTO flex_brickphone_group_members (group_id, identifier, name, role) VALUES (?, ?, ?, ?)',
        { groupId, targetIdentifier, playerName(targetSrc), role == 'admin' and 'admin' or 'member' }
    )
    emitHook('groupMemberAdded', groupId, src, targetSrc)
    RefreshBrickPhoneContacts(targetSrc)
    return true
end)

exports('RemoveGroupMember', function(groupId, src, targetSrc)
    local identifier = getIdentifier(src)
    local targetIdentifier = getIdentifier(targetSrc)
    if not identifier or not targetIdentifier or not canManage(groupId, identifier) or identifier == targetIdentifier then return false end
    MySQL.update.await('DELETE FROM flex_brickphone_group_members WHERE group_id = ? AND identifier = ?', { groupId, targetIdentifier })
    emitHook('groupMemberRemoved', groupId, src, targetSrc)
    RefreshBrickPhoneContacts(targetSrc)
    return true
end)

exports('GetGroupMembers', function(groupId, src)
    if not src then return {} end
    local identifier = getIdentifier(src)
    if not identifier or not isMember(groupId, identifier) then return {} end
    return MySQL.query.await('SELECT identifier, name, role, joined_at FROM flex_brickphone_group_members WHERE group_id = ?', { groupId })
end)

exports('IsGroupMember', function(groupId, src)
    local identifier = getIdentifier(src)
    return identifier and isMember(groupId, identifier) or false
end)

exports('IsGroupAdmin', function(groupId, src)
    local identifier = getIdentifier(src)
    return identifier and canManage(groupId, identifier) or false
end)

exports('SetGroupOwner', function(groupId, src, targetSrc)
    local identifier = getIdentifier(src)
    local targetIdentifier = getIdentifier(targetSrc)
    if not identifier or not targetIdentifier or memberRole(groupId, identifier) ~= 'owner' or not isMember(groupId, targetIdentifier) then
        return false
    end

    local existingOwnedGroupId = ownedGroupId(targetIdentifier)
    if existingOwnedGroupId and tonumber(existingOwnedGroupId) ~= tonumber(groupId) then
        groupDebug(
            'SetGroupOwner blocked: target %s already owns active group %s',
            tostring(targetIdentifier),
            tostring(existingOwnedGroupId)
        )
        return false
    end

    MySQL.update.await('UPDATE flex_brickphone_group_members SET role = "admin" WHERE group_id = ? AND identifier = ?', { groupId, identifier })
    MySQL.update.await('UPDATE flex_brickphone_group_members SET role = "owner" WHERE group_id = ? AND identifier = ?', { groupId, targetIdentifier })
    MySQL.update.await('UPDATE flex_brickphone_groups SET owner_identifier = ? WHERE id = ?', { targetIdentifier, groupId })
    emitHook('groupOwnerChanged', groupId, targetSrc)
    RefreshBrickPhoneContacts(targetSrc)
    return true
end)

exports('InviteGroupMember', function(groupId, src, targetSrc)
    local identifier = getIdentifier(src)
    local targetIdentifier = getIdentifier(targetSrc)
    if not identifier or not targetIdentifier or not canManage(groupId, identifier) then return false end
    if isMember(groupId, targetIdentifier) then return false end
    local existing = MySQL.scalar.await(
        'SELECT id FROM flex_brickphone_group_invites WHERE group_id = ? AND target_identifier = ? AND status = ? AND expires_at > NOW()',
        { groupId, targetIdentifier, 'pending' }
    )
    if existing then return false end
    local group = dbGroup(groupId)
    if not group then return false end
    local inviteId = MySQL.insert.await([[
        INSERT INTO flex_brickphone_group_invites
            (group_id, target_identifier, inviter_identifier, inviter_name, expires_at)
        VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))
    ]], { groupId, targetIdentifier, identifier, playerName(src), Config.Groups.inviteExpiry })
    if targetSrc and GetPlayerName(targetSrc) then
        sendGroupSystemMessage(targetSrc,
            locale('groups.invite_received'):format(playerName(src), group.name, groupId),
            'groups')
    end
    emitHook('groupInviteSent', groupId, src, targetSrc, inviteId)
    return inviteId
end)

exports('SetGroupContactName', function(groupId, src, contactId, displayName)
    local identifier = getIdentifier(src)
    if not identifier or not canManage(groupId, identifier) or type(displayName) ~= 'string' then return false end
    local changed = MySQL.update.await(
        'UPDATE flex_brickphone_group_contacts SET display_name = ? WHERE group_id = ? AND contact_id = ?',
        { displayName:sub(1, 100), groupId, contactId }
    )
    return changed > 0
end)

exports('SendGroupMessage', function(groupId, src, message, messageType)
    return sendGroupMessage(groupId, src, message, messageType)
end)

exports('GetGroupMessages', function(groupId, src)
    return groupMessages(src, groupId) or {}
end)

exports('AddGroupContact', function(groupId, src, contactId, displayName, contactType, phoneIdentifier, permissions)
    local identifier = getIdentifier(src)
    if not identifier or not canManage(groupId, identifier) then return false end
    if type(contactId) ~= 'string' or contactId == '' then return false end
    local result = MySQL.insert.await([[
        INSERT INTO flex_brickphone_group_contacts
            (group_id, contact_id, display_name, contact_type, phone_identifier, permissions, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { groupId, contactId, displayName or contactId, contactType or 'contact', phoneIdentifier, permissions and json.encode(permissions) or nil, identifier })
    emitHook('groupContactAdded', groupId, src, contactId)
    return result ~= nil
end)

exports('RemoveGroupContact', function(groupId, src, contactId)
    local identifier = getIdentifier(src)
    if not identifier or not canManage(groupId, identifier) then return false end
    local changed = MySQL.update.await('DELETE FROM flex_brickphone_group_contacts WHERE group_id = ? AND contact_id = ?', { groupId, contactId })
    if changed > 0 then emitHook('groupContactRemoved', groupId, src, contactId) end
    return changed > 0
end)

exports('GetGroupContacts', function(groupId, src)
    local identifier = getIdentifier(src)
    if not identifier or not isMember(groupId, identifier) then return {} end
    return MySQL.query.await('SELECT * FROM flex_brickphone_group_contacts WHERE group_id = ?', { groupId })
end)

exports('RegisterGroupHook', function(eventName, handler)
    if type(eventName) ~= 'string' or type(handler) ~= 'function' then return false end
    groupHandlers[eventName] = handler
    return true
end)

function GetBrickPhoneGroupId(contactId)
    return groupIdFromContact(contactId)
end

function GetBrickPhoneGroups(src)
    return loadGroupsForPlayer(src)
end

function GetBrickPhoneGroupMessages(src, groupId)
    return groupMessages(src, groupId)
end

function GetBrickPhoneSendMessage(groupId, src, message, messageType)
    return sendGroupMessage(groupId, src, message, messageType)
end
AddEventHandler('playerDropped', function()
    local src = source
    local identifier = getIdentifier(src)
    if not identifier then return end

    local rows = MySQL.query.await([[
        SELECT gm.group_id, g.name
        FROM flex_brickphone_group_members gm
        INNER JOIN flex_brickphone_groups g ON g.id = gm.group_id
        WHERE gm.identifier = ? AND g.status = 'active'
    ]], { identifier })

    for _, row in ipairs(rows or {}) do
        notifyGroup(row.group_id, locale('groups.member_disconnected'):format(playerName(src)))
        emitHook('groupMemberDisconnected', row.group_id, src)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    MySQL.update('DELETE FROM flex_brickphone_group_invites WHERE expires_at <= NOW() OR status <> "pending"')
end)

CreateThread(function()
    while true do
        Wait(60000)
        MySQL.update('DELETE FROM flex_brickphone_group_invites WHERE expires_at <= NOW() OR status <> "pending"')
    end
end)
