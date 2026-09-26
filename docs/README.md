# Flex BrickPhone — Quick Setup & Examples

This resource is a FiveM phone with normal contacts, group conversations, a Crafter contact, skill/job restrictions, mission GPS routes, and exports for other resources.

## Requirements

- `ox_lib`
- `oxmysql`
- `ox_inventory`
- `ox_target`
- `qbx_core`

The resource uses Qbox for the optional job restriction feature.

## Basic configuration

Edit `shared/config.lua` for contacts and `shared/sv_shared.lua` for crafting recipes/pickup locations.

### A normal contact

```lua
['dispatcher'] = {
    id = 'dispatcher',
    name = 'contacts.dispatcher_name',
    number = '555-911',
    enabled = true
}
```

### A contact restricted to multiple Qbox jobs

```lua
['emergency'] = {
    id = 'emergency',
    name = 'contacts.emergency_name',
    number = '555-EMS',
    enabled = true,
    job = { 'police', 'ambulance' }
}
```

The player must have either `police` or `ambulance`.

### Require the player to be on duty

```lua
['police_dispatch'] = {
    id = 'police_dispatch',
    name = 'contacts.police_dispatch_name',
    number = '555-POLICE',
    enabled = true,
    job = { 'police' },
    onDuty = true
}
```

`job` can also be a single string:

```lua
job = 'police'
```

The server checks the job every time the contact is opened or used, so this is not only a UI restriction.

## Groups — easy examples

Open the **Groups** contact and send these messages.

### Create a group

```text
create Street Crew
```

Dutch locale:

```text
maak Street Crew
```

**Leadership limit:** each player can lead/own only **one active group**. This does not limit how many groups they can join as a normal member, so a player can belong to 100+ groups.

If a player already leads a group, creating another group is rejected. The same rule is enforced by the `CreateGroup` server export.

### See your groups

```text
list
```

Dutch:

```text
lijst
```

### Invite player ID 25 to group 3

```text
invite 3 25
```

Dutch:

```text
uitnodig 3 25
```

### Accept an invitation

```text
accept 3
```

### See group members

```text
members 3
```

Dutch:

```text
leden 3
```

### Rename a group

Owner/admin:

```text
rename 3 Street Crew 2
```

Dutch:

```text
hernoem 3 Street Crew 2
```

### Leave a group

```text
leave 3
```

**Important:** leaving the group no longer automatically deletes the group. Groups are only permanently deleted with `disband` unless `Config.Groups.deleteEmptyGroups` is explicitly enabled.

### Permanently delete a group

Owner only:

```text
 disband 3
```

Dutch:

```text
opheffen 3
```

### Find the group a player administers

Server-side:

```lua
local groupId = exports.flex_brickphone:GetAdminGroupId(source)

if groupId then
    print(('Admin group: %s'):format(groupId))
end
```

The export checks active memberships and returns the owned group first, otherwise the first active group where the player has the `admin` role.

## Crafting — easy examples

Open the **Crafter** contact.

### See recipes

```text
list
```

Dutch:

```text
lijst
```

### Add an item

```text
pistol 2
```

The recipe's `orderingName` is used for the command, while the ox_inventory label is used for display.

### View the current cart

```text
order
```

### Remove items from the cart

```text
remove pistol 1
```

### Clear the cart

```text
clear
```

### Start crafting

```text
confirm
```

### Check active crafting orders

```text
status
```

Example response:

```text
Crafting status:

- Pistol x2 — `1724000000_1` — 42s remaining
- Lockpick x1 — `1724000000_2` — ready for pickup
```

### Cancel an active order

```text
cancel 1724000000_1
```

Cancelling removes the active order and releases its pickup location. Crafting materials are consumed only when the finished item is successfully picked up, so cancelling does not require a material refund.

## Crafting pickup GPS

When an order becomes ready:

1. The server sends the exact configured `vector4` pickup coordinates.
2. The client creates the pickup zone.
3. The client creates the crafting ped when the player enters the zone.
4. The ped uses the `vector4.w` heading.
5. The ped is spawned at `z + 1.0` to prevent it from being buried in the ground.
6. A GPS route is created to the crafting pickup.
7. When the order is collected/cancelled, the route is removed or moved to another ready pickup.

Example:

```lua
Config.SV_Config.pickUpZones = {
    [1] = vector4(-330.0, -140.0, 38.0, 180.0),
    [2] = vector4(1100.0, -2000.0, 30.0, 90.0)
}
```

The fourth value is the ped heading.

## Runtime contact example

Register a contact from another resource:

```lua
exports.flex_brickphone:registerContact(
    'dispatcher',
    {
        id = 'dispatcher',
        name = 'Dispatcher',
        number = '555-911',
        enabled = true,
        job = { 'police', 'ambulance' }
    },
    function(source, data)
        if data.message:lower() == 'start' then
            TriggerClientEvent('myresource:startMission', source)

            exports.flex_brickphone:sendContactMessage(
                source,
                'dispatcher',
                '**Mission started.** Your route is now active.'
            )

            return {
                received = true,
                accepted = true
            }
        end

        return false
    end
)
```

The handler receives:

- `source` — server ID
- `data.message` — player message
- `data.contact` — contact configuration
- `data.contactId` — contact ID
- `data.skill` — skill data when configured
- `data.job` — Qbox job data when the contact has a job restriction

Example `data.job`:

```lua
{
    name = 'police',
    grade = 2,
    onDuty = true
}
```

## Mission GPS example

```lua
exports.flex_brickphone:startMission(source, {
    coords = vector4(-330.0, -140.0, 38.0, 180.0),
    label = 'Mission Pickup',
    contactId = 'dispatcher',
    message = '**Mission started.** Follow the GPS route.'
})
```

## Useful exports

### Open / close

Client:

```lua
exports.flex_brickphone:openPhone()
exports.flex_brickphone:closePhone()
```

### Send a server-side phone message

```lua
exports.flex_brickphone:sendContactMessage(
    source,
    'dispatcher',
    'Your mission is ready.'
)
```

### Register a handler

```lua
exports.flex_brickphone:registerContactHandler('dispatcher', function(source, data)
    return true
end)
```

### Remove a contact

```lua
exports.flex_brickphone:removeContact('dispatcher')
```

## UI message handling

Incoming structured messages are normalized by the NUI. If a contact accidentally sends a Lua/JS object instead of a string, the phone now extracts `.text`, `.message`, or `.content`, and otherwise renders the object as JSON instead of showing `[object Object]`.

## Debugging

Set:

```lua
Config.Debug = true
```

The server console will show the contact/message path, including group command handling and database operations.

For normal use keep it disabled.


## Minimum police / emergency-services count

A contact can require a minimum number of players in one or more Qbox jobs before the contact is shown or usable.

### Basic example

```lua
['emergency_dispatch'] = {
    id = 'emergency_dispatch',
    name = 'contacts.emergency_dispatch_name',
    number = '911',
    enabled = true,
    policeCount = {
        jobs = { 'police', 'bcso' },
        count = 1
    }
}
```

This means:

- Count `police` players.
- Count `bcso` players.
- Add both counts together.
- The contact is available when the total is **1 or more**.

For example:

```text
police:  1
bcso:    0
---------
total:   1  -> allowed
```

or:

```text
police:  0
bcso:    2
---------
total:   2  -> allowed
```

But:

```text
police:  0
bcso:    0
---------
total:   0  -> blocked
```

### Require 2 players

```lua
policeCount = {
    jobs = { 'police', 'bcso' },
    count = 2
}
```

### What is counted?

By default this uses Qbox's `GetDutyCountJob()` export, so **only on-duty players count**. This is the recommended setup for police/emergency-service requirements.

If you intentionally want to count all online players in those jobs, regardless of duty status:

```lua
policeCount = {
    jobs = { 'police', 'bcso' },
    count = 2,
    onDuty = false
}
```

The check is performed server-side when contacts are built, opened, and used, so it cannot be bypassed by only changing the NUI.

### Multiple job names

You can use as many jobs as you need:

```lua
policeCount = {
    jobs = { 'police', 'bcso', 'sheriff', 'state' },
    count = 3
}
```

The count is the combined total across all unique job names in `jobs`.

### Handler data

If the contact has a server-side handler, the handler receives the current requirement information:

```lua
exports.flex_brickphone:registerContactHandler('emergency_dispatch', function(source, data)
    print(('Emergency count: %s/%s'):format(
        data.policeCount.current,
        data.policeCount.required
    ))

    return true
end)
```

`data.policeCount` contains:

```lua
{
    current = 3,
    required = 2,
    jobs = { 'police', 'bcso' },
    onDuty = true
}
```
