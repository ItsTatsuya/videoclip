--[[
Copyright: Ajatt-Tools and contributors; https://github.com/Ajatt-Tools
License: GNU GPL, version 3 or later; http://www.gnu.org/licenses/gpl.html

Timings class
]]

local Timings = {
    ['start'] = -1,
    ['end'] = -1,
}

function Timings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Timings:reset()
    self['start'] = -1
    self['end'] = -1
end

function Timings:normalize()
    if self['start'] >= 0 and self['end'] >= 0 and self['start'] > self['end'] then
        self['start'], self['end'] = self['end'], self['start']
        return true
    end
    return false
end

function Timings:validate()
    self:normalize()
    return self['start'] >= 0 and self['start'] < self['end']
end

function Timings:duration()
    if not self:validate() then
        return 0
    end
    return self['end'] - self['start']
end

return Timings
