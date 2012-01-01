--
-- $Date $Revision$
--

NQS = LibStub("AceAddon-3.0"):NewAddon(
    "NADTQuestShare",
    "AceConsole-3.0",
	"AceComm-3.0",
	"AceEvent-3.0"
)

local playerName = UnitName("player")
local quests = {}
local oldquests = {}
local firstscan = true

-- meta table of qlinks to qids
NQS.qids = setmetatable({}, {
	__index = function(t,i)
		local v = tonumber(i:match("|Hquest:(%d+):"))
		t[i] = v
		return v
	end,
})

function NQS:OnEnable()

	-- common
	self:QUEST_LOG_UPDATE()
	self:RegisterEvent("QUEST_LOG_UPDATE")

	-- master
	if NQS_DB.mode == "master" then
		self:Print("NADTQuestShare initialized - master")
	end
	
	-- slave
	if NQS_DB.mode == "slave" then
		self:RegisterEvent("QUEST_ACCEPT_CONFIRM")
		self:Print("NADTQuestShare initialized - slave")
	end
	
	-- register for addon messages
	self:RegisterComm("nqs")

end

-- handle incoming addon messages
function NQS:OnCommReceived(prefix, message, distribution, sender)

	-- actions
	-- ACCEPTED qlink = sender accepted a quest
	-- TURNEDIN qlink = sender turned in a quest
	-- DOYOUHAVE qid = sender wants to know if we have a specifid quest in our log
	-- DONOTHAVE qid = sender does not have a specific quest in their log

	if prefix ~= "nqs" or distribution ~= "PARTY" or sender == playerName or not NTL:IsUnitTrusted(sender) then return end
	
	local verb, qlink = message:match( "^(%S+) (.+)$" )
	
	if verb == "ACCEPTED" then
		self:Print(sender, "accepted", qlink)
	elseif verb == "TURNEDIN" then
		self:Print(sender, "turned in", qlink)
	elseif verb == "DOYOUHAVE" then
		if NQS_DB.mode == "slave" then
			if not quests[self.qids[qlink]] then
				SendAddonMessage( "nqs", "DONOTHAVE " .. qlink, "PARTY" )
			end
		end
	elseif verb == "DONOTHAVE" then
		if NQS_DB.mode == "master" then
			self:ShareQuestById(self.qids[qlink])
		end
	end
end

-- accepts quests shared to us by trusted people
function NQS:QUEST_ACCEPT_CONFIRM(name, qname)
	if not NTL:UnitIsTrusted(name) then return end
	self:Print("Accepting quest", qname, "started by", name)
	ConfirmAcceptQuest()
	StaticPopup_Hide("QUEST_ACCEPT")
end

-- our quest log has changed
function NQS:QUEST_LOG_UPDATE(event)
	
	quests, oldquests = oldquests, quests
	wipe(quests)
	
	-- build up a map of the quest in our log, qid => qlink
	for i = 1, GetNumQuestLogEntries() do
		local qlink = GetQuestLink(i)
		if qlink then quests[self.qids[qlink]] = qlink end
	end

	-- break out early if there are no old quests to compare to
	if firstscan then
		firstscan = nil
		return
	end
	
	-- iterate over old quests, reporting as turned in any that aren't in current
	for qid, qlink in pairs(oldquests) do
		if not quests[qid] then
			if not abandoning then
				SendAddonMessage( "nqs", "TURNEDIN " .. qlink, "PARTY" )
			end
		end
	end
	abandoning = nil
	
	-- iterate over current quests, checking for ones that aren't in the old list
	for qid, qlink in pairs(quests) do
		if not oldquests[qid] then
			SendAddonMessage( "nqs", "ACCEPTED " .. qlink, "PARTY" )
			if NQS_DB.mode == "master" then
				SendAddonMessage( "nqs", "DOYOUHAVE " .. qlink, "PARTY" )
			end
		end
	end
	
end

-- share a quest by id
function NQS:ShareQuestById(qid)

	-- find the quest
	local title, thisqid
	for i = 1, GetNumQuestLogEntries() do
		local thisqid = select(9, GetQuestLogTitle(i))
		if qid == thisqid then
			local qlink = GetQuestLink(i)
			SelectQuestLogEntry( i )
			if GetQuestLogPushable() then
				-- only share in trusted parties
				if NTL:IsGroupTrusted() then
					QuestLogPushQuest()
				else
					self:Print("not in a trusted party - not sharing ", qlink)
				end
			else
				self:Print(qlink, "is not shareable")
			end
		end
	end
	
end

-- this lets us distinguish between turning in and abandoning a quest
local orig = AbandonQuest
function AbandonQuest(...)
	abandoning = true
	return orig(...)
end


--
-- EOF
