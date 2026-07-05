using Godot;

namespace Game.Database;

/// <summary>
/// Read-only wrapper around a GDScript GRDRow GodotObject.
/// Provides typed accessors for row values via dotted path resolution.
/// </summary>
public class GrdRow
{
    protected readonly GodotObject Inner;

    public GrdRow(GodotObject inner)
    {
        Inner = inner;
    }

    /// <summary>Raw row identifier resolved from the configured id_field.</summary>
    public Variant RawId => Inner.Call("get_id");

    /// <summary>The underlying Godot Resource.</summary>
    public Resource? Resource => Inner.Call("get_resource").AsGodotObject() as Resource;

    /// <summary>Returns true when the dotted path resolves (value may still be null).</summary>
    public bool HasPath(string path) => Inner.Call("has_path", path).AsBool();

    /// <summary>All visible column names.</summary>
    public StringName[] Keys
    {
        get
        {
            var array = Inner.Call("keys").AsGodotArray<StringName>();
            if (array is null || array.Count == 0)
                return [];
            var result = new StringName[array.Count];
            for (var i = 0; i < array.Count; i++)
                result[i] = array[i];
            return result;
        }
    }

    /// <summary>Returns the raw Variant at the given path.</summary>
    public Variant GetVariant(string path) => Inner.Call("get_value", path);

    /// <summary>Returns the string value, or defaultValue when the path is missing or the value is not a string.</summary>
    public string GetString(string path, string defaultValue = "")
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType is Variant.Type.String or Variant.Type.StringName
            ? v.AsString()
            : defaultValue;
    }

    /// <summary>Returns the int value, or defaultValue when the path is missing or the value is not an int.</summary>
    public int GetInt(string path, int defaultValue = 0)
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType == Variant.Type.Int ? v.AsInt32() : defaultValue;
    }

    /// <summary>Returns the float value, or defaultValue when the path is missing or the value is not numeric.</summary>
    public float GetFloat(string path, float defaultValue = 0.0f)
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType switch
        {
            Variant.Type.Float => (float)v.AsDouble(),
            Variant.Type.Int => v.AsInt32(),
            _ => defaultValue,
        };
    }

    /// <summary>Returns the bool value, or defaultValue when the path is missing or the value is not a bool.</summary>
    public bool GetBool(string path, bool defaultValue = false)
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType == Variant.Type.Bool ? v.AsBool() : defaultValue;
    }

    /// <summary>Returns the StringName value, or defaultValue when the path is missing or the value is not a StringName/String.</summary>
    public StringName GetStringName(string path, StringName? defaultValue = null)
    {
        var v = Inner.Call("get_value", path);
        if (v.VariantType == Variant.Type.StringName)
            return v.AsStringName();
        if (v.VariantType == Variant.Type.String)
            return v.AsString();
        return defaultValue ?? string.Empty;
    }

    /// <summary>Returns the value as a Resource of type T, or null when missing or not the expected type.</summary>
    public T? GetResource<T>(string path) where T : Resource
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType == Variant.Type.Object ? v.AsGodotObject() as T : null;
    }

    /// <summary>Returns the GodotObject at the given path, or null when missing or not an object.</summary>
    public GodotObject? GetGodotObject(string path)
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType == Variant.Type.Object ? v.AsGodotObject() : null;
    }

    /// <summary>Returns the Vector3 value, or defaultValue when the path is missing or the value is not a Vector3.</summary>
    public Vector3 GetVector3(string path, Vector3? defaultValue = null)
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType == Variant.Type.Vector3 ? v.AsVector3() : defaultValue ?? default;
    }

    /// <summary>Returns the Godot Array at the given path, or an empty array when missing or not an array.</summary>
    public Godot.Collections.Array GetArray(string path)
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType == Variant.Type.Array ? v.AsGodotArray() : new Godot.Collections.Array();
    }

    /// <summary>Returns the Godot Dictionary at the given path, or an empty dictionary when missing or not a dictionary.</summary>
    public Godot.Collections.Dictionary GetDictionary(string path)
    {
        var v = Inner.Call("get_value", path);
        return v.VariantType == Variant.Type.Dictionary ? v.AsGodotDictionary() : new Godot.Collections.Dictionary();
    }
}
