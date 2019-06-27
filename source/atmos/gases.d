module atmos.gases;

import atmos.constants;

//Basic gas datum

struct GasDatum
{
    string id = "";
    SpecificHeatCapacity specificHeat = 0*specHeatUnit;
    string name = "";
    int rarity = 0;
    string gasOverlay = "";
    AmountOfSubstance molesVisible = -1*mole;
    bool dangerous = false;
    int fusionPower = 0;
}

//enum that holds the gases -- all the other stuff is sort of compile-time expanded from this

pragma(msg,"Defining gases. Gases found:");

enum Gases : GasDatum
{
    Oxygen = GasDatum( 
        "o2",
        20*specHeatUnit,
        "Oxygen",
        900 ),
    Nitrogen = GasDatum( 
        "n2",
        20*specHeatUnit,
        "Nitrogen",
        1000),
    CO2 = GasDatum(  // what the fuck is this?
        "co2",
        30*specHeatUnit,
        "Carbon Dioxide",
        700),
    Plasma = GasDatum(
        "plasma",
        200*specHeatUnit,
        "Plasma", 
        800,
        "plasma",
        molesGasVisible,
        true ),
    WaterVapor = GasDatum(
        "water_vapor",
        40*specHeatUnit,
        "Water Vapor",
        500,
        "water_vapor",
        molesGasVisible,
        false,
        8),
    HyperNoblium = GasDatum(
        "nob",
        2000*specHeatUnit,
        "Hyper-noblium",
        50,
        "freon",
        molesGasVisible,
        true),
    NitrousOxide = GasDatum(
        "n2o",
        40*specHeatUnit,
        "Nitrous Oxide",
        600,
        "nitrous_oxide",
        molesGasVisible * 2,
        true,
        10),
    Nitryl= GasDatum(
        "no2",
        20*specHeatUnit,
        "Nitryl",
        100,
        "nitryl",
        molesGasVisible,
        true,
        16 ),
    Tritium = GasDatum(
        "tritium",
        10*specHeatUnit,
        "Tritium",
        300,
        "tritium",
        molesGasVisible,
        true,
        1),

    Bz = GasDatum(
        "bz",
        20*specHeatUnit,
        "BZ",
        400,
        "",
        -1*mole,
        true,
        8),

    Stimulum = GasDatum(
        "stim",
        5*specHeatUnit,
        "Stimulum",
        1,
        "",
        -1*mole,
        false,
        7),

    Pluoxium=GasDatum(
        "pluox",
        80*specHeatUnit,
        "Pluoxium",
        200,
        "",
        -1*mole,
        false,
        -10),
        
    Miasma=GasDatum(
        "miasma",
        20*specHeatUnit,
        "Miasma",
        250,
        "miasma",
        molesGasVisible * 60
    )
}

import std.traits : EnumMembers;

import std.algorithm.sorting : sort;

enum gasesAsMembers = [ EnumMembers!Gases ].sort!("a.rarity>b.rarity");

enum numGases = gasesAsMembers.length;

private enum compiledOut = gasesAsMembers.release;

enum gasesAsArray = cast(GasDatum[numGases])(compiledOut);

pragma(msg,gasesAsArray.length);

GasDatum getGas(string s)() /// Gets gas by ID.
{
    static foreach(gas; gasesAsArray)
    {
        if(gas.id==s || gas.name==s)
        {
            return gas;
        }
    }
    assert(0,"No gas found with ID '"~s~"'!");
}

//functions that work with gas datums--GasDatum itself should be plain ol data, UFCS makes the syntax look nice anyway

pure nothrow @nogc @safe HeatCapacity heatCapacity(GasDatum gas,AmountOfSubstance amount)
{
    return gas.specificHeat*amount;
}