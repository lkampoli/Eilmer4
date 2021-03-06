/** json_helper.d
 * Some convenience functions to help with parsing JSON values from the config files.
 *
 * Author: Peter J.
 * Initial code: 2015-02-05
 */

module json_helper;

import std.json;
import std.conv;
import geom;

// TODO: lots of repetition here, use templates.

string getJSONstring(JSONValue jsonData, string key, string defaultValue)
{
    string value;
    try {
        value = to!string(jsonData[key].str);
    } catch (Exception e) {
        value = defaultValue;
    }
    return value;
} // end getJSONstring()

int getJSONint(JSONValue jsonData, string key, int defaultValue)
{
    int value;
    try {
        value = to!int(jsonData[key].integer);
    } catch (Exception e) {
        value = defaultValue;
    }
    return value;
} // end getJSONint()

double getJSONdouble(JSONValue jsonData, string key, double defaultValue)
{
    double value;
    try {
        auto json_val = jsonData[key];
        // We wish to accept value like 0.0 or 0
        if (json_val.type() == JSONType.float_) {
            value = json_val.floating;
        } else {
            value = to!double(json_val.str);
        }
    } catch (Exception e) {
        value = defaultValue;
    }
    return value;
} // end getJSONdouble()

bool getJSONbool(JSONValue jsonData, string key, bool defaultValue)
{
    bool value;
    try {
        value = jsonData[key].type is JSONType.true_;
    } catch (Exception e) {
        value = defaultValue;
    }
    return value;
} // end getJSONbool()

int[] getJSONintarray(JSONValue jsonData, string key, int[] defaultValue)
{
    int[] value;
    try {
        auto json_values = jsonData[key].array;
        foreach (json_val; json_values) {
            value ~= to!int(json_val.integer);
        }
    } catch (Exception e) {
        value = defaultValue;
    }
    return value;
} // end getJSONintarray()

double[] getJSONdoublearray(JSONValue jsonData, string key, double[] defaultValue)
{
    double[] value;
    try {
        auto json_values = jsonData[key].array;
        foreach (json_val; json_values) {
            // We wish to accept value like 0.0 or 0
            if (json_val.type() == JSONType.float_) {
                value ~= json_val.floating;
            } else {
                value ~= to!double(json_val.str);
            }
        }
    } catch (Exception e) {
        value = defaultValue;
    }
    return value;
} // end getJSONdoublearray()


Vector3 getJSONVector3(JSONValue jsonData, string key, Vector3 defaultValue)
// Read a Vector3 value as an array of 3 floating-point values.
{
    Vector3 value;
    try {
        auto json_values = jsonData[key].array;
        foreach (i, json_val; json_values) {
            switch (i) {
            case 0: value.refx = to!double(json_val.floating); break;
            case 1: value.refy = to!double(json_val.floating); break;
            case 2: value.refz = to!double(json_val.floating); break;
            default:
            }
        }
    } catch (Exception e) {
        value = defaultValue;
    }
    return value;
} // end getJSONVector3()
