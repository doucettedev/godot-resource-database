using System;
using System.Collections;
using System.Collections.Generic;
using Godot;

namespace Game.Database;

/// <summary>
/// Fluent, clone-on-chain query builder wrapping a GDScript GRDQuery.
/// Every chain method returns a new GrdQuery wrapping the inner call's result.
/// </summary>
public class GrdQuery<TRow> : IEnumerable<TRow> where TRow : GrdRow
{
    private readonly GodotObject _inner;
    private readonly Func<GodotObject, TRow> _factory;

    public GrdQuery(GodotObject inner, Func<GodotObject, TRow> factory)
    {
        _inner = inner;
        _factory = factory;
    }

    // -----------------------------------------------------------------------
    // Filter chain methods
    // -----------------------------------------------------------------------

    public GrdQuery<TRow> WhereEq(string fieldPath, Variant value)
    {
        var inner = _inner.Call("where_eq", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> WhereNe(string fieldPath, Variant value)
    {
        var inner = _inner.Call("where_ne", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> WhereGt(string fieldPath, Variant value)
    {
        var inner = _inner.Call("where_gt", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> WhereGte(string fieldPath, Variant value)
    {
        var inner = _inner.Call("where_gte", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> WhereLt(string fieldPath, Variant value)
    {
        var inner = _inner.Call("where_lt", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> WhereLte(string fieldPath, Variant value)
    {
        var inner = _inner.Call("where_lte", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> WhereIn(string fieldPath, Godot.Collections.Array value)
    {
        var inner = _inner.Call("where_in", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> WhereContains(string fieldPath, Variant value)
    {
        var inner = _inner.Call("where_contains", fieldPath, value).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    // -----------------------------------------------------------------------
    // Ordering / pagination chain methods
    // -----------------------------------------------------------------------

    public GrdQuery<TRow> OrderBy(string fieldPath, bool ascending = true)
    {
        var inner = _inner.Call("order_by", fieldPath, ascending).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> Limit(int count)
    {
        var inner = _inner.Call("limit", count).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    public GrdQuery<TRow> Offset(int count)
    {
        var inner = _inner.Call("offset", count).AsGodotObject();
        return new GrdQuery<TRow>(inner, _factory);
    }

    // -----------------------------------------------------------------------
    // Terminal execution
    // -----------------------------------------------------------------------

    public TRow[] ToArray()
    {
        var array = _inner.Call("to_array").AsGodotArray();
        if (array is null || array.Count == 0)
            return [];
        var result = new TRow[array.Count];
        for (var i = 0; i < array.Count; i++)
            result[i] = _factory(array[i].AsGodotObject()!);
        return result;
    }

    public TRow? First()
    {
        var obj = _inner.Call("first").AsGodotObject();
        return obj is not null ? _factory(obj) : null;
    }

    public int Count => _inner.Call("count").AsInt32();

    public string[] Ids()
    {
        return _inner.Call("ids").AsStringArray();
    }

    // -----------------------------------------------------------------------
    // IEnumerable<TRow>
    // -----------------------------------------------------------------------

    public IEnumerator<TRow> GetEnumerator()
    {
        var array = ToArray();
        for (var i = 0; i < array.Length; i++)
            yield return array[i];
    }

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();
}
