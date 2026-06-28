---@class lugo.ValidationContext
---@field contract string
---@field field string

---@class lugo.Validator<T>
---@field name string
---@field validate fun(value: any, context: lugo.ValidationContext): lugo.Error|nil

---@alias lugo.StructFields table<string, lugo.Validator<any>>

---@class lugo.Struct<T>: table
---@field name string
---@field fields lugo.StructFields
---@field instance_metatable table
---@field new fun(self: lugo.Struct<T>, value: table): T|nil, lugo.Error|nil
---@field check fun(self: lugo.Struct<T>, value: any): T|nil, lugo.Error|nil
---@field is fun(self: lugo.Struct<T>, value: any): boolean

---@class lugo.Interface<T>: table
---@field name string
---@field members lugo.StructFields
---@field check fun(self: lugo.Interface<T>, value: any): T|nil, lugo.Error|nil
---@field is fun(self: lugo.Interface<T>, value: any): boolean

---@class lugo.struct
local struct = {}

local errors = require("lugo.errors")

local Struct = {}
Struct.__index = Struct

local Interface = {}
Interface.__index = Interface

---@param value any
---@return string
local function actual_type(value)
    if value == nil then
        return "nil"
    end
    return type(value)
end

---@param contract string
---@param field string
---@param expected string
---@param value any
---@return lugo.Error
local function invalid_field_error(contract, field, expected, value)
    return errors.new("contract field has invalid type", {
        kind = "contract_invalid_field",
        fields = {
            contract = contract,
            field = field,
            expected = expected,
            actual = actual_type(value),
        },
    })
end

---@generic T
---@param name string
---@param validate fun(value: any): boolean
---@return lugo.Validator<T>
local function validator(name, validate)
    return {
        name = name,
        validate = function(value, context)
            if validate(value) then
                return nil
            end

            return invalid_field_error(context.contract, context.field, name, value)
        end,
    }
end

struct.any = validator("any", function()
    return true
end)

struct.string = validator("string", function(value)
    return type(value) == "string"
end)

struct.number = validator("number", function(value)
    return type(value) == "number"
end)

struct.boolean = validator("boolean", function(value)
    return type(value) == "boolean"
end)

struct.table = validator("table", function(value)
    return type(value) == "table"
end)

struct.function_ = validator("function", function(value)
    return type(value) == "function"
end)

---@generic T
---@param base lugo.Validator<T>
---@return lugo.Validator<T|nil>
function struct.optional(base)
    return {
        name = base.name .. "?",
        validate = function(value, context)
            if value == nil then
                return nil
            end

            return base.validate(value, context)
        end,
    }
end

---@param contract string
---@param value any
---@return lugo.Error
local function not_table_error(contract, value)
    return errors.new("contract value must be a table", {
        kind = "contract_not_table",
        fields = {
            contract = contract,
            actual = actual_type(value),
        },
    })
end

---@param contract string
---@param field string
---@return lugo.Error
local function missing_field_error(contract, field)
    return errors.new("required contract field is missing", {
        kind = "contract_missing_field",
        fields = {
            contract = contract,
            field = field,
            actual = "nil",
        },
    })
end

---@param name string
---@param fields lugo.StructFields
---@param value any
---@return lugo.Error|nil
local function validate_fields(name, fields, value)
    if type(value) ~= "table" then
        return not_table_error(name, value)
    end

    for field, field_validator in pairs(fields) do
        local field_value = value[field]
        local err = field_validator.validate(field_value, {
            contract = name,
            field = field,
        })
        if err ~= nil then
            if field_value == nil then
                return missing_field_error(name, field)
            end
            return err
        end
    end

    return nil
end

---@generic T
---@param name string
---@param fields lugo.StructFields
---@return lugo.Struct<T>
function struct.struct(name, fields)
    ---@type lugo.Struct<any>
    local result = setmetatable({
        name = name,
        fields = fields,
    }, Struct)

    result.instance_metatable = {
        __index = result,
    }

    return result
end

---@generic T
---@param name string
---@param members lugo.StructFields
---@return lugo.Interface<T>
function struct.interface(name, members)
    return setmetatable({
        name = name,
        members = members,
    }, Interface)
end

---@generic T
---@param self lugo.Struct<T>
---@param value table
---@return T|nil value
---@return lugo.Error|nil err
function Struct:new(value)
    local err = validate_fields(self.name, self.fields, value)
    if err ~= nil then
        return nil, err
    end

    local mt = getmetatable(value)
    if mt ~= nil and mt ~= self.instance_metatable then
        return nil, errors.new("struct value already has a different metatable", {
            kind = "struct_metatable_conflict",
            fields = {
                struct = self.name,
            },
        })
    end

    setmetatable(value, self.instance_metatable)
    return value, nil
end

---@generic T
---@param self lugo.Struct<T>
---@param value any
---@return T|nil value
---@return lugo.Error|nil err
function Struct:check(value)
    if type(value) == "table" and getmetatable(value) == self.instance_metatable then
        return value, nil
    end

    return nil, errors.new("value is not this struct", {
        kind = "struct_not_instance",
        fields = {
            struct = self.name,
            actual = actual_type(value),
        },
    })
end

---@generic T
---@param self lugo.Struct<T>
---@param value any
---@return boolean
function Struct:is(value)
    return type(value) == "table" and getmetatable(value) == self.instance_metatable
end

---@generic T
---@param self lugo.Interface<T>
---@param value any
---@return T|nil value
---@return lugo.Error|nil err
function Interface:check(value)
    local err = validate_fields(self.name, self.members, value)
    if err ~= nil then
        return nil, err
    end

    return value, nil
end

---@generic T
---@param self lugo.Interface<T>
---@param value any
---@return boolean
function Interface:is(value)
    return self:check(value) ~= nil
end

return struct
