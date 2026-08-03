States = {
	QUEUED = 1,
	JOINING = 2,
	JOINED = 3,
	DISCONNECTED = 4,
}

function PlayerClass(identifier, player, deferrals)
	local member = FetchDatabaseUser(identifier, player)
	if not member or member == "" or member == -1 then
		return nil
	end

	if GetConvar("danger_everyone_is_admin", "") == "1" then -- everyone is management when this convar is 1
		local hasManagement = false
		for _, group in ipairs(member.groups) do
			if group == "Management" then
				hasManagement = true
				break
			end
		end
		if not hasManagement then
			table.insert(member.groups, "Management")
		end
	end

	local prio = 0
	local msg = ""

	if member.priority then
		local prioBoosts = tonumber(member.priority)
		if prioBoosts and prioBoosts > 0 then
			msg = "\n🎉 Extra Priority Boosts | +" .. prioBoosts
			prio = prio + prioBoosts
		end
	end

	if QUEUE.Dropped:Get(identifier) then
		msg = msg .. "\n💥 Crash Priority | +1000"
		prio = prio + 1000
	end

	local tempPrio = QUEUE.TempPriority:Get(identifier)
	if tempPrio then
		msg = msg .. string.format("\n🦖 Temporary Priority | +%s", tempPrio.Priority)
		prio = prio + tempPrio.Priority
	end

	for _, group in ipairs(member.groups) do
		if Config.Groups[group] and Config.Groups[group].Queue and Config.Groups[group].Queue.Priority > 0 then
			prio = prio + tonumber(Config.Groups[group].Queue.Priority)

			msg = msg
				.. "\n"
				.. string.format(
					"%s | +%s",
					Config.Groups[group].Queue.Message or Config.Groups[group].Name,
					Config.Groups[group].Queue.Priority
				)
		end
	end

	if member.priority > 0 then
		msg = "\n🌟 Base Priority | +" .. member.priority .. " 🌟" .. msg
	end

	while prio == nil do
		Wait(10)
	end

	local _data = {
		Source = player,
		State = States.QUEUED,
		ID = member._id,
		Groups = member.groups,
		Name = member.name,
		AccountID = member.account,
		Avatar = member.avatar,
		Tokens = member.tokens,
		Identifier = identifier,
		Verified = member.verified,
		Priority = prio,
		Message = msg,
		TimeBoost = 0,
		Deferrals = deferrals,
		Grace = nil,

		Timer = {
			Hour = 0,
			Minute = 0,
			Second = 0,

			Tick = function(self, plyr)
				if self.Second == 59 then
					if self.Minute == 59 then
						self.Second = 0
						self.Minute = 0
						self.Hour = self.Hour + 1
					else
						self.Second = 0
						self.Minute = self.Minute + 1
					end

					if plyr.TimeBoost < Config.Settings.MaxTimeBoost then
						plyr.TimeBoost = plyr.TimeBoost + 1
						plyr.Priority = plyr.Priority + 1
					end
				else
					self.Second = self.Second + 1
				end
			end,
			Output = function(self)
				return string.format("%02d:%02d:%02d", self.Hour, self.Minute, self.Second)
			end,
		},

		IsWhitelisted = function(self)
			if _tempWhitelist[self.ID] then
				return true
			end

			-- print(type(plsr.Convar.ACCESS_ROLE.value))
			if plsr.Convar.ACCESS_ROLE.value == "0" then
				return true
			end

			if #member.groups > 0 then
				local accessRole = plsr.Convar.ACCESS_ROLE.value or "Whitelisted"
				for _, group in ipairs(member.groups) do
					if
						Config.Groups[group]
						and (
							(Config.Groups[group].Abv == accessRole)
							or (type(Config.Groups[group].Permission) == "table" and Config.Groups[group].Permission.Level >= 10)
							or _tempWhitelistGroup[Config.Groups[group].Abv]
						)
					then
						return true
					end
				end
			end

			return false
		end,

		IsBanned = function(self)
			return (
				plsr.Punishment:CheckBan("account", self.AccountID)
				or plsr.Punishment:CheckBan("identifier", self.Identifier)
			)
		end,

		IsVerified = function(self)
			return self.Verified
		end,

		IsTokenBanned = function(self)
			local tkns = {}
			for i = 0, GetNumPlayerTokens(self.Source) - 1 do
				table.insert(tkns, GetPlayerToken(self.Source, i))
			end

			return plsr.Punishment:CheckTokenBan(tkns)
		end,

		IsInGracePeriod = function(self)
			if self.Grace == nil then
				return false
			else
				return os.time() <= self.Grace + (60 * Config.Settings.Grace)
			end
		end,
	}

	return _data
end

local _usersTableReady = false
local function ensureUsersTable(callback)
	if _usersTableReady then
		if callback then
			callback()
		end
		return
	end
	plsr.Database:Query(
		"CREATE TABLE IF NOT EXISTS `users` (`id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, `identifier` VARCHAR(191) NOT NULL, `account` BIGINT UNSIGNED NOT NULL, `name` VARCHAR(191) NOT NULL, `groups` JSON NOT NULL, `data` JSON NOT NULL, UNIQUE INDEX `idx_identifier` (`identifier`), UNIQUE INDEX `idx_account` (`account`))",
		nil,
		function()
			_usersTableReady = true
			if callback then
				callback()
			end
		end
	)
end

function FetchDatabaseUser(identifier, player)
	local p = promise.new()

	ensureUsersTable(function()
		plsr.Database:Single("SELECT `id`, `account`, `name`, `groups`, `data` FROM `users` WHERE `identifier` = ?", { identifier }, function(success, row)
			if success and row ~= nil then
				local ok, existing = pcall(json.decode, row.data)
				if ok and type(existing) == "table" then
					existing._id = row.id
					existing.identifier = identifier
					existing.account = row.account
					existing.name = row.name

					local groupsOk, groups = pcall(json.decode, row.groups)
					existing.groups = (groupsOk and type(groups) == "table") and groups or {}

					--[[
						Added this check to update player names if they've changed
						Also checking to see if player name was nil and if so
						Update it as well, but even on player join, it should
						prevent them from joining with an empty name
					]]
					--
					local currentName = GetPlayerName(player)
					if row.name == nil or row.name ~= currentName then
						existing.name = currentName
						plsr.Database:Update("UPDATE `users` SET `name` = ? WHERE `id` = ?", { currentName, row.id }, function()
							p:resolve(existing)
						end)
					else
						p:resolve(existing)
					end
					return
				end
			end

			local account = plsr.Sequence:Get("Account")
			local name = GetPlayerName(player)
			local groups = { "Whitelisted" }
			local doc = {
				name = name,
				account = account,
				identifier = identifier,
				verified = true,
				joined = os.time() * 1000,
				priority = 0,
			}
			plsr.Database:Insert(
				"INSERT INTO `users` (`identifier`, `account`, `name`, `groups`, `data`) VALUES (?, ?, ?, ?, ?)",
				{ identifier, account, name, json.encode(groups), json.encode(doc) },
				function(insertSuccess, newId)
					doc._id = newId
					doc.groups = groups
					p:resolve(doc)
				end
			)
		end)
	end)

	return Citizen.Await(p)
end
