-- Initializing global variables to store the latest game state and game host process.
LatestGameState = LatestGameState or nil
InAction = InAction or false -- Prevents the agent from taking multiple actions at once.
nearestEnemy =nearestEnemy or nil

Logs = Logs or {}

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

function addLog(msg, text) -- Function definition commented for performance, can be used for debugging
  Logs[msg] = Logs[msg] or {}
  table.insert(Logs[msg], text)
end


function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end


function findWeakestEnemy()
  local weakestPlayer = nil
  local minHealth = math.huge

  for target, state in pairs(LatestGameState.Players) do
      if target ~= ao.id and state.health < minHealth then
          weakestPlayer = state
          minHealth = state.health
      end
  end

  return weakestPlayer
end

-- Calculate boundaries
function isValidPosition(x, y)
  return x >= 0 and x <= LatestGameState.GameWidth and y >= 0 and y <= LatestGameState.GameHeight
end

function calculateMove(direction,me,enemy)
  local dx=0
  local dy=0
  if direction==false then
     dx = me.x - enemy.x
     dy = me.y - enemy.y 
  else
     dx = enemy.x - me.x 
     dy = enemy.y - me.y 
  end

  local magnitude = math.sqrt(dx^2 + dy^2)
  dx = dx / magnitude
  dy = dy / magnitude

  local newX = me.x + dx
  local newY = me.y + dy
  if isValidPosition(newX,newY) then
    ao.send({ Target = Game, Action = "Move", Player = ao.id, X = newX, Y = newY })
    InAction = false
  end
end

function randomMovement(nearby)
  local me = LatestGameState.Players[ao.id]
  if nearby then
    calculateMove(false,me,nearby)
  end
end


function moveToEnemy()
  local me = LatestGameState.Players[ao.id]
  if nearestEnemy then
    calculateMove(true,me,nearestEnemy)
  end
end


function attackNearestEnemy()

  -- If you find the one with the lowest health, then don't look for it
  if not nearestEnemy then
    nearestEnemy = findWeakestEnemy()
  end
  local me = LatestGameState.Players[ao.id]
  local targetInRange = false
  if nearestEnemy and inRange(me.x, me.y, nearestEnemy.x, nearestEnemy.y, 1) then
    targetInRange = true
  end

  -- If it's near him, launch an attack. If it's not there, continue moving
  if targetInRange and me.energy > 0.3 then
      local attackEnergy = me.energy * 0.5 
      print(colors.red .. "Attacking nearest enemy with energy: " .. attackEnergy .. colors.reset)
      ao.send({ Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(attackEnergy) })
      InAction = false
  elseif targetInRange == false then
    moveToEnemy()
  end
end

-- Decide whether to evade or pursue the next step
function attackWeakestPlayer()
  local me = LatestGameState.Players[ao.id]
  local nearby=nil;
  local index=0;

  --Find people nearby
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id and inRange(me.x, me.y, state.x, state.y, 3) then
      index=index+1
      nearby=state
    end
  end

  --If the health is low, determine the number of people nearby
  --If there is a person nearby with low health, mark them as launching an attack
  --If there are multiple people nearby or if my health is higher than mine, move in the opposite direction
  if me.health < 0.3 then
    if index == 1 and me.health>nearby.health then
      nearestEnemy=health
      attackNearestEnemy()
    elseif (index == 1 and me.health<=nearby.health) or index > 1 then
      randomMovement(nearby)
    end
  else
    attackNearestEnemy()
  end

  
end


function decideNextAction()
  if not InAction then
      InAction = true
      attackWeakestPlayer()
  end
end




Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true -- InAction logic added
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then -- InAction logic added
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print \'LatestGameState\' for detailed view.")
  end
)

Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false -- InAction logic added
      return
    end
    print("Deciding next action.")
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then -- InAction logic added
      InAction = true -- InAction logic added
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == undefined then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Player has no energy."})
      else
        print(colors.red .. "Returning attack." .. colors.reset)
        ao.send({Target = Game, Action = "PlayerAttack", Player = ao.id, AttackEnergy = tostring(playerEnergy)})
      end
      InAction = false -- InAction logic added
      ao.send({Target = ao.id, Action = "Tick"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)
