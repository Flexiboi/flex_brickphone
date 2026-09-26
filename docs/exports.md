# Flex BrickPhone — Integration & Export Guide

This resource is designed so other FiveM resources can use the phone without editing BrickPhone internals.

## 1. Send a message to a contact and receive a callback

Use the client export when a player needs to send a message to a configured contact.

```lua
exports.flex_brickphone:replyToContact(
    'dispatcher',
    'start mission',
    function(result)
        if result == true then
            print('The contact received the request.')
        elseif result == false then
            print('The contact rejected the request.')
        elseif type(result) == 'table' then
            print(result.message or 'The contact returned data.')
        end
    end
)
```

The callback receives the exact value returned by the server-side contact handler.

A handler can return:

```lua
return true
```

```lua
return false
```

or structured data:

```lua
return {
    received = true,
    accepted = true,
    missionId = 12345,
    message = 'Mission accepted.'
}
```

## 2. Register your own contact handler

Register the contact first in `Config.Contacts`, or create it at runtime with `registerContact`.

```lua
exports.flex_brickphone:registerContactHandler('dispatcher', function(source, data)
    local message = data.message:lower()

    if message == 'start mission' then
        TriggerClientEvent('myresource:startMission', source)

        exports.flex_brickphone:sendContactMessage(
            source,
            'dispatcher',
            '### Mission Started\nYour mission has been accepted.'
        )

        return {
            received = true,
            accepted = true
        }
    end

    return false
end)
```

The handler receives:

| Value | Meaning |
|---|---|
| `source` | Player server ID |
| `data.message` | Player message |
| `data.contactId` | Contact ID |
| `data.contact` | Full contact configuration |
| `data.skill` | Current skill data |

## 3. Register a contact at runtime

```lua
exports.flex_brickphone:registerContact(
    'dispatcher',
    {
        id = 'dispatcher',
        name = 'Dispatcher',
        number = '555-911',
        enabled = true,
        target = 'all' -- 'all' or a player server ID
    },
    function(source, data)
        return {
            received = true,
            accepted = true
        }
    end
)
```

The handler is optional. `registerContact` is a **server-side export**. Runtime contacts are added to the same server-side contact registry used by `Config.Contacts`, so they appear in the normal contact list. The list is refreshed immediately for currently connected players and is rebuilt from the registry when players open the phone later, including players who join after the contact was registered.

### Contact targeting

By default, a runtime contact targets the whole server (`target = 'all'`). To assign the contact to one specific player, use that player's server ID:

```lua
exports.flex_brickphone:registerContact(
    'dispatcher_private',
    {
        id = 'dispatcher_private',
        name = 'Private Dispatcher',
        number = '555-912',
        enabled = true,
        target = 42
    },
    function(source, data)
        return { received = true, accepted = true }
    end
)
```

You can also pass the target as the fourth argument instead of putting it in the contact table:

```lua
exports.flex_brickphone:registerContact('dispatcher', {
    id = 'dispatcher',
    name = 'Dispatcher',
    number = '555-911',
    enabled = true
}, handler, 42)
```

`target = 'all'` exposes the contact to every player. A numeric target exposes it only to that server ID. The same target restriction is enforced when opening conversations, sending messages, and sending server-side contact messages.

## 4. Remove a runtime contact

```lua
exports.flex_brickphone:removeContact('dispatcher')
```

## 5. Remove a contact handler

```lua
exports.flex_brickphone:unregisterContactHandler('dispatcher')
```

## 6. Send a contact message from the server

This puts a message into the player's conversation and sends it to the phone immediately.

```lua
exports.flex_brickphone:sendContactMessage(
    source,
    'dispatcher',
    '### Update\nThe delivery location has changed.'
)
```

If the phone is closed, the player also receives a small animated SMS popup.

### Editing a pending crafting order

Before confirming an order, players can edit it from the Crafter conversation:

```text
order
```

View the current order.

```text
remove pistol 2
```

Removes 2x Pistol. The ordering name is the value configured as `orderingName`, not the ox_inventory spawn name.

```text
remove pistol
```

Removes all Pistol entries from the pending order.

```text
clear
```

Clears the entire pending order.

The `remove` and `clear` commands are localized through the locale JSON files.

## 7. Start a mission

```lua
exports.flex_brickphone:startMission(source, {
    coords = vector4(-330.0, -140.0, 38.0, 180.0),
    label = 'Mission Pickup',
    contactId = 'dispatcher',
    message = '**Mission started.** Check your route.'
})
```

This creates the route and optionally sends the first contact message.

## 8. Open and close the phone

Client-side:

```lua
exports.flex_brickphone:openPhone()
```

```lua
exports.flex_brickphone:closePhone()
```

The phone animation and `prop_prologue_phone` are started/stopped with the UI.

## 9. Send a message directly to the open UI

Client-side:

```lua
exports.flex_brickphone:sendContactMessage(
    'dispatcher',
    '**Your mission is ready.**'
)
```

Use the server export instead when the message originates from server gameplay logic.

## 10. Set a phone mission waypoint

Client-side:

```lua
exports.flex_brickphone:setPhoneWaypoint(
    vector4(-330.0, -140.0, 38.0, 180.0),
    'Mission Pickup'
)
```

---

# Crafting

## Recipe configuration

Each recipe supports its own crafting time:

```lua
Config.SV_Config.crafterItems = {
    ['pistol'] = {
        name = 'crafter.item_gun',
        reward = 'weapon_pistol',
        craftTime = 30,
        materials = {
            { item = 'steel', amount = 10 },
            { item = 'plastic', amount = 5 }
        }
    }
}
```

`craftTime` is measured in **seconds per item**.

For example:

```text
pistol 3
```

with `craftTime = 30` takes:

```text
90 seconds total
30 seconds per pistol
```

## Ordering multiple items

The crafter accepts:

```text
pistol
```

```text
pistol 3
```

```text
pistol x3
```

```text
3 pistol
```

The maximum amount per order is configured here:

```lua
Config.Crafting.maxQuantityPerOrder = 5
```

Multiple separate orders can also be active at the same time:

```lua
Config.Crafting.maxActiveOrders = 5
```

Materials are reserved when the order is accepted. This prevents a player from placing several orders with the same inventory items.

Reserved materials are refunded if the player logs out or disconnects before pickup.

---

# Pickup security

Pickup validation is performed on the server.

The client sends the network ID of the synced pickup ped. The server validates:

- The order belongs to the player.
- The order is ready.
- The network entity exists.
- The entity uses the configured pickup ped model.
- The player is close enough to the ped.
- The player is inside the pickup zone.
- The ped is still close to the configured pickup coordinates.
- The order has not already been collected.

An invalid pickup distance or entity causes the server to reject the request and can kick the player using the configured exploit locale.

The client also uses `lib.zones.sphere`, so pickup peds and their `ox_target` targets only exist while the player is inside the configured zone.

---

# Client cleanup

The resource removes:

- Phone prop
- Phone animation
- Pickup peds
- `ox_target` local entities
- `ox_lib` pickup zones
- Mission blips
- NUI focus

Cleanup happens when:

```lua
QBCore:Client:OnPlayerUnload
```

fires or when the resource stops.

Server-side crafting reservations are also cleared on logout/disconnect.

## Crafter recipe labels

Crafter orders use the **ox_inventory label of the reward item** instead of a separate translated recipe name. This means the same recipe automatically follows the label configured by ox_inventory.

Example recipe:

```lua
['pistol'] = {
    reward = 'weapon_pistol',
    craftTime = 30,
    materials = {
        { item = 'steel', amount = 10 },
        { item = 'plastic', amount = 5 }
    }
}
```

If ox_inventory defines `weapon_pistol` with the label `Pistol`, the player can order:

```text
Pistol
Pistol 3
3 Pistol
```

Multi-word labels are supported too, for example `Heavy Pistol 2`.

The Crafter list also uses ox_inventory labels for both the reward and required materials, so translations stay in one place.

The list command is localized with `crafter.commands.list` in the locale JSON.

## Locale setup

BrickPhone uses ox_lib's locale module. Set the server language in `server.cfg`:

```cfg
setr ox:locale "en"
```

or:

```cfg
setr ox:locale "nl"
```

Restart the resource after changing the locale. Locale files are in `locales/en.json` and `locales/nl.json`.

The Crafter's `list`, `order`, `confirm`, and `clear` commands are read from the active locale, and all Crafter response text is translated from the same locale file.

## Crafter ordering names

Each crafting recipe can define its own player-facing `orderingName`. This is the text the player sends to the Crafter. It does not have to match the recipe ID, reward item name, or ox_inventory label.

```lua
['pistol_recipe'] = {
    orderingName = 'pistol',
    reward = 'weapon_pistol',
    craftTime = 30,
    materials = {
        { item = 'lockpick', amount = 2 },
        { item = 'steel', amount = 5 }
    }
}
```

Players can then send `pistol 2` to add two pistols to their order. The command is case-insensitive, so `PISTOL 2`, `Pistol 2`, and `pIsToL 2` all match the same recipe. The craft list displays the `orderingName` as the value to type, while the crafted item and material names shown to the player still come from `ox_inventory` labels.


# Group Messaging API

Groups are a native extension of the existing BrickPhone contact/message flow. Group IDs are server-generated and all membership/permission checks are server-side.

## Server exports

### `CreateGroup(source, name, avatar?)`
Creates a persistent group and makes `source` the owner/leader.

**Ownership limit:** a player can own/lead **one active group only**. This does not limit membership; a player can join as a member of any number of groups.

If the player already owns an active group, creation is rejected and the export returns `false`.

Returns: `number|false`.

```lua
local groupId = exports.flex_brickphone:CreateGroup(source, 'Police Operations')

if not groupId then
    print('Player already leads a group or the group could not be created.')
end
```

The same one-group ownership rule is enforced by the in-phone `create <name>` command.

### `DeleteGroup(groupId, source)`
Owner-only disband. Removes members, contacts and pending invites.

Returns: `boolean`.

### `GetGroup(groupId)`
Returns the persisted group row or `nil`.

### `GetGroups(source)`
Returns all active groups the player belongs to as BrickPhone contact-shaped records.

Membership is not limited by the one-group leadership rule; a player can join many groups.

### `AddGroupMember(groupId, source, targetSource, role?)`
Owner/admin-only membership addition. `role` may be `member` or `admin`.

### `RemoveGroupMember(groupId, source, targetSource)`
Owner/admin-only removal.

### `GetGroupMembers(groupId, source)`
Returns members only when `source` is a member.

### `IsGroupMember(groupId, source)`
Returns `boolean`.

### `IsGroupAdmin(groupId, source)`
Returns `boolean` for owner/admin.

### `GetAdminGroupId(source)`
Returns the group ID of the player's first active group where they have an `owner` or `admin` role.

The query prioritizes the player's owned group if they have one, then the lowest group ID among their admin groups. Returns `number|nil`.

```lua
local adminGroupId = exports.flex_brickphone:GetAdminGroupId(source)

if adminGroupId then
    print(('Player administers group %s'):format(adminGroupId))
end
```

This export is useful when another resource needs to find the group a player administers without already knowing the group ID.

### `SetGroupOwner(groupId, source, targetSource)`
Owner-only ownership transfer.

### `InviteGroupMember(groupId, source, targetSource)`
Creates an expiring invite for an online player.

Returns: invite ID or `false`.

### `SendGroupMessage(groupId, source, message, messageType?)`
Server-authoritative group send. It stores the message once and delivers it to each currently online member. Offline members receive the persisted history when they reopen the conversation.

```lua
exports.flex_brickphone:SendGroupMessage(
    groupId,
    source,
    '10-4, everyone meet at Mission Row.'
)
```

### `GetGroupMessages(groupId, source)`
Returns persisted group history if `source` is a member.

### `AddGroupContact(groupId, source, contactId, displayName, contactType?, phoneIdentifier?, permissions?)`
Owner/admin-only persistent group contact.

### `RemoveGroupContact(groupId, source, contactId)`
Owner/admin-only removal.

### `SetGroupContactName(groupId, source, contactId, displayName)`
Owner/admin-only rename.

### `GetGroupContacts(groupId, source)`
Returns group contacts if `source` is a member.

### `RegisterGroupHook(eventName, handler)`
Registers a server-side handler for a group lifecycle hook.

```lua
exports.flex_brickphone:RegisterGroupHook('groupMessageReceived', function(groupId, recipient, sender, message)
    -- Custom resource logic.
end)
```

## Group events

All events use the `flex_brickphone:` prefix:

- `groupCreated(groupId, source, name)`
- `groupDeleted(groupId, source)`
- `groupMemberAdded(groupId, source, targetSource)`
- `groupMemberRemoved(groupId, source, targetSource)`
- `groupInviteSent(groupId, inviter, target, inviteId)`
- `groupInviteAccepted(groupId, target, inviterIdentifier, inviteId)`
- `groupInviteDeclined(groupId, target, inviterIdentifier, inviteId)`
- `groupMemberLeft(groupId, source)`
- `groupMemberDisconnected(groupId, source)`
- `groupOwnerChanged(groupId, newOwner)`
- `groupMessageSent(groupId, sender, message)`
- `groupMessageReceived(groupId, recipient, sender, message)`
- `groupContactAdded(groupId, source, contactId)`
- `groupContactRemoved(groupId, source, contactId)`

`groupMessageReceived` is emitted once for every eligible online member, including the sender.

## In-phone Groups contact

The built-in `groups` contact supports localized commands:

- `help`
- `list`
- `create <name>`
- `invite <group id> <player server id>`
- `accept <group id>`
- `decline <group id>`
- `leave <group id>`
- `remove <group id> <player server id>`
- `disband <group id>`
- `contacts <group id>`
- `addcontact <group id> <contact id> <display name>`
- `removecontact <group id> <contact id>`
- `renamecontact <group id> <contact id> <display name>`

Command words are read from `locales/*.json`, so they can be translated without changing Lua.

## Persistence

The resource creates these tables automatically with oxmysql:

- `flex_brickphone_groups`
- `flex_brickphone_group_members`
- `flex_brickphone_group_messages`
- `flex_brickphone_group_invites`
- `flex_brickphone_group_contacts`

No manual migration is required for a fresh install. Existing BrickPhone message/contact behavior is left intact.

## Security

Client input is never trusted for group ownership, membership, role, sender identity or group existence. Group sends, member changes, invites and contact changes are checked against the server database.

Ownership is also validated server-side. A player may be a member of unlimited groups, but only one active group can have that player's identifier as `owner_identifier`. Ownership transfer is rejected if the target already owns another active group.


## Implementation notes

The existing individual contact/message flow remains in `server/main.lua` and the existing NUI. Group support is isolated in `server/groups.lua` and uses group contact IDs (`group:<id>`) so existing phone navigation and Markdown rendering are reused. The original session-based individual message storage is unchanged; group messages are additionally persisted because groups are server-persistent.

## 11. Job-restricted contacts (Qbox)

Contacts can be restricted to one or more Qbox jobs.

Single job:

```lua
job = 'police'
```

Multiple jobs:

```lua
job = { 'police', 'ambulance' }
```

Require the player to be on duty as well:

```lua
job = { 'police', 'ambulance' },
onDuty = true
```

The check is performed server-side when the contact is listed, opened, and used. A contact handler also receives:

```lua
{
    name = 'police',
    grade = 2,
    onDuty = true
}
```

as `data.job`.

## 12. Group commands

English examples:

```text
create Street Crew
list
invite 3 25
members 3
rename 3 Street Crew 2
leave 3
disband 3
```

Dutch examples:

```text
maak Street Crew
lijst
uitnodig 3 25
leden 3
hernoem 3 Street Crew 2
verlaten 3
opheffen 3
```

Groups are not deleted simply because all members are offline or the last member leaves. Use `disband` for intentional deletion.

## 13. Crafter status and cancellation

Check active/pending orders:

```text
status
```

Cancel an active order:

```text
cancel <order-id>
```

The order ID is shown by `status` and in the pickup information. Cancelling releases the pickup slot. Materials are consumed only during successful pickup, so cancellation does not require a material refund.

## 14. Crafting pickup GPS

Crafting pickup positions should be configured as `vector4` values:

```lua
Config.SV_Config.pickUpZones = {
    [1] = vector4(-330.0, -140.0, 38.0, 180.0),
}
```

The values are:

```text
x, y, z, heading
```

The client uses the same position for the pickup zone and GPS route, uses `w` for the ped heading, and spawns the ped at `z + 1.0`.
