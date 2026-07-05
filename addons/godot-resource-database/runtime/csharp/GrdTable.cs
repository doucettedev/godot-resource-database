using System;
using Godot;

namespace Game.Database;

/// <summary>
/// Typed wrapper around a GDScript GRDTable. Delegates all operations to the
/// inner GodotObject and maps raw row objects through the provided factory.
/// </summary>
public class GrdTable<TRow> where TRow : GrdRow
{
    private readonly GodotObject _inner;
    private readonly Func<GodotObject, TRow> _factory;

    public GrdTable(GodotObject inner, Func<GodotObject, TRow> factory)
    {
        _inner = inner;
        _factory = factory;
    }

    /// <summary>Number of rows in the table.</summary>
    public int Size => _inner.Call("size").AsInt32();

    /// <summary>Returns true when the table contains a row with the given id.</summary>
    public bool Has(string id) => _inner.Call("has_row", id).AsBool();

    /// <summary>Returns the typed row for the given id, or null if not found.</summary>
    public TRow? Get(string id)
    {
        var row = _inner.Call("get_row", id).AsGodotObject();
        return row is not null ? _factory(row) : null;
    }

    /// <summary>Returns the typed row for the given id, or null if not found.</summary>
    public TRow? TryGet(string id) => Get(id);

    /// <summary>Returns all rows as a new array.</summary>
    public TRow[] All()
    {
        var array = _inner.Call("all").AsGodotArray();
        if (array is null || array.Count == 0)
            return [];
        var result = new TRow[array.Count];
        for (var i = 0; i < array.Count; i++)
            result[i] = _factory(array[i].AsGodotObject()!);
        return result;
    }

    /// <summary>Returns the live row array (read-only reference; do not mutate).</summary>
    public TRow[] AllReadonly()
    {
        var array = _inner.Call("all_readonly").AsGodotArray();
        if (array is null || array.Count == 0)
            return [];
        var result = new TRow[array.Count];
        for (var i = 0; i < array.Count; i++)
            result[i] = _factory(array[i].AsGodotObject()!);
        return result;
    }

    /// <summary>Returns all rows where the field equals value. Builds a lazy index on first call.</summary>
    public TRow[] WhereEq(string fieldPath, Variant value)
    {
        var array = _inner.Call("where_eq", fieldPath, value).AsGodotArray();
        if (array is null || array.Count == 0)
            return [];
        var result = new TRow[array.Count];
        for (var i = 0; i < array.Count; i++)
            result[i] = _factory(array[i].AsGodotObject()!);
        return result;
    }

    /// <summary>Returns the first row where field equals value, or null.</summary>
    public TRow? FindEq(string fieldPath, Variant value)
    {
        var row = _inner.Call("find_eq", fieldPath, value).AsGodotObject();
        return row is not null ? _factory(row) : null;
    }

    /// <summary>Creates a new query builder for this table.</summary>
    public GrdQuery<TRow> Query()
    {
        var queryInner = _inner.Call("query").AsGodotObject()!;
        return new GrdQuery<TRow>(queryInner, _factory);
    }

    /// <summary>Builds a lazy equality index on the given field path.</summary>
    public void EnsureIndex(string fieldPath) => _inner.Call("ensure_index", fieldPath);

    /// <summary>Clears the equality index for the given field path.</summary>
    public void ClearIndex(string fieldPath) => _inner.Call("clear_index", fieldPath);

    /// <summary>Clears all equality indexes.</summary>
    public void ClearIndexes() => _inner.Call("clear_indexes");

    /// <summary>Returns all row IDs.</summary>
    public string[] RowIds()
    {
        return _inner.Call("row_ids").AsStringArray();
    }
}
