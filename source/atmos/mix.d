module atmos.mix;

import atmos;

/** 
    Can be treated as a AmountOfSubstance[GasDatum] for all intents and purposes, but automatically asserts gases.
    It should be noted that iteration over the whole list is no slower for this.
*/
struct GasEntries 
{
    AmountOfSubstance[GasDatum] gases; /// Gases by datum.
    bool dirty = true; /// Whether or not the gas entry has been added to recently.
    alias gases this;
    /** Accessing directly by gas datum instead of accessing gases, e.g. GasEntries[getGas!"plasma"] */
    pure @safe AmountOfSubstance opIndex(GasDatum gas)
    {
        return gases.get(gas,0*mole);
    }
    /** Same as above, but assignment.
        Actually does some further calculation: leads to undefined behavior of the mole total is less than 0,
        if the mole total EQUALS zero then it deletes that particular entry for faster reactions,
        if the mole total is more than previous it sets the entire GasEntries to dirty to flag it ready to maybe react.*/
    pure @safe AmountOfSubstance opIndexAssign(AmountOfSubstance moles,GasDatum gas)
    in
    {
        assert(moles>=0*mole,"A negative mole value was assigned to "~gas.name~"!");
    }
    do
    {
        if(moles == 0*mole)
        {
            gases.remove(gas);
            return 0*mole;
        }
        else
        {
            dirty = moles>this[gas];
            return gases[gas]=moles;
        }
    }
    /**
        Same as assignment, but for +=, -=, *= and /=. Note that + and - require proper units--you need to input moles!
    */
    pure @safe AmountOfSubstance opIndexOpAssign(string op,T)(T value,GasDatum gas)
    {
        import std.traits : isNumeric;
        static if(((op=="/" || op=="*") && isNumeric!T) || ((op=="+" || op=="-") && is(T : AmountOfSubstance)))
        {
            auto newAmount = mixin("this[gas]"~op~"value");
            return opIndexAssign(newAmount,gas);
        }
        else
        {
            import std.traits : fullyQualifiedName;
            assert(0,`Invalid operator "` ~op~`" for type `~fullyQualifiedName!T~`!`);
        }
    }
}
/**
    Proper atmos mixture. Stores all the required stuff, can calculate the rest as needed.
*/
struct AtmosMixture
{
    GasEntries gases; /// See GasEntries.
    alias gases this;
    Temperature temperature = 0*kelvin; /// Current temperature in kelvins.
    Volume volume = cellVolume; /// Volume. Default is 2500 liters.
    AmountOfSubstance lastShare = 0*mole; /// Unused for now, until a more accurate-to-SS13 mixing operation is put in.
    ReactionFlag previousResult = ReactionFlag.NO_REACTION; /// For faster reaction caching.
    this(Volume newVolume) /// Making a new mixture with a given volume, in liters.
    {
        volume=newVolume;
    }
    this(float newVolume) /// Making a new mixture with a given volume. Float will be converted to liters.
    {
        this(newVolume*liter);
    }
    pure @nogc @safe HeatCapacity heatCapacity() /// Returns current heat capacity of mixture, in joules/kelvin.
    {
        HeatCapacity totalAmount=0*heatCapacityUnit;
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            totalAmount+=gas.heatCapacity(amount);
        }
        return totalAmount;
    }
    pure @nogc @safe AmountOfSubstance totalMoles() /// Returns the total moles currently in the mixture, in moles.
    {
        AmountOfSubstance totalAmount = 0*mole;
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            totalAmount+=amount;
        }
        return totalAmount;
    }
    pure @nogc @safe Pressure pressure() /// Returns pressure, in pascals.
    in
    {
        assert(volume>0*liter); //no division by zero
    }
    do
    {
        return (gasConstant*totalMoles*temperature)/volume;
    }
    pure @nogc @safe Energy thermalEnergy() /// Returns thermal energy, in joules.
    {
        return heatCapacity*temperature;
    }
    pure @safe void merge(AtmosMixture other) /// Merges this atmos mixture with another.
    {
        temperature = (thermalEnergy + other.thermalEnergy) / (heatCapacity + other.heatCapacity);
        foreach(GasDatum gas,AmountOfSubstance amount;other.gases)
        {
            this.gases[gas]+=amount;
        }
    }
    pure @safe AtmosMixture remove(AmountOfSubstance amount) /// Removes a certain amount of moles from mix; returns mixture with all removed substance.
    {
        import std.algorithm.comparison : min;
        auto removed = AtmosMixture();
        const auto cachedTotal = totalMoles;
        amount = min(amount,cachedTotal);
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            removed.gases[gas] = (amount / cachedTotal)*amount;
            amount -= removed.gases[gas];
        }
        return removed;
    }
    pure @safe AtmosMixture removeRatio(float ratio) /// Removes a percentage of substance from mix; returns mixture with all removed substance.
    in
    {
        assert(ratio>0);
    }
    do
    {
        import std.algorithm.comparison : min;
        ratio = min(ratio,1);
        auto removed = AtmosMixture();
        const auto cachedTotal = totalMoles;
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            removed.gases[gas] = amount * ratio;
            amount -= removed.gases[gas];
        }
        return removed;
    }
    pure @safe Pressure share(AtmosMixture other, int adjacentTurfs = 4) /// A port of /tg/'s sharing code.
    {
        //none of you are free of sin
        import std.math : abs;
        const auto temperatureDelta = temperature - other.temperature;
        const auto absTemperatureDelta = abs(temperatureDelta.value(kelvin))*kelvin;
        const auto oldSelfHeatCapacity = heatCapacity;
        const auto oldOtherHeatCapacity = other.heatCapacity;
        HeatCapacity heatCapacitySelfToOther;
        HeatCapacity heatCapacityOtherToSelf;
        AmountOfSubstance movedMoles = 0*mole;
        AmountOfSubstance absMovedMoles = 0*mole;
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            auto delta = (amount - other[gas])/(adjacentTurfs+1);
            auto gasHeatCapacity = gas.heatCapacity(delta);
            if(delta>0*mole)
            {
                heatCapacitySelfToOther += gasHeatCapacity;
            }
            else
            {
                heatCapacityOtherToSelf -= gasHeatCapacity;
            }
            auto absMolesThisTime=abs(delta.value(mole))*mole;
            if(absMolesThisTime>0.1*mole)
            {
                this[gas] -= delta;
                other[gas] += delta;
                movedMoles += delta;
                absMovedMoles += absMolesThisTime;
            }
        }
        if(absMovedMoles>0.1*mole)
        {
            lastShare = absMovedMoles;
            auto newSelfHeatCapacity = oldSelfHeatCapacity + heatCapacityOtherToSelf - heatCapacitySelfToOther;
            auto newOtherHeatCapacity = oldOtherHeatCapacity + heatCapacitySelfToOther - heatCapacityOtherToSelf;
            temperature = (oldSelfHeatCapacity*temperature - heatCapacitySelfToOther*temperature + heatCapacityOtherToSelf*other.temperature)/newSelfHeatCapacity;

            other.temperature = (oldOtherHeatCapacity*other.temperature-heatCapacityOtherToSelf*other.temperature + heatCapacitySelfToOther*temperature)/newOtherHeatCapacity;
            temperatureShare(other, openHeatTransferCoefficient);
            return (temperature*(totalMoles + movedMoles) - other.temperature*(other.totalMoles - movedMoles)) * gasConstant / volume;
        }
        else
        {
            temperatureShare(other, openHeatTransferCoefficient);
            return 0*pascal;
        }
    }
    pure @nogc @safe Temperature temperatureShare(AtmosMixture other,float conductionCoefficient) /// Port of /tg/ temperature share.
    {
        import std.math : abs;
        import std.algorithm.comparison : max;
        auto temperatureDelta=temperature-other.temperature;
        if(abs(temperatureDelta.value(kelvin))<0.1)
        {
            return other.temperature;
        }
        auto selfHeatCapacity = heatCapacity;
        auto otherHeatCapacity = other.heatCapacity;
        auto heat = conductionCoefficient*temperatureDelta*(selfHeatCapacity*otherHeatCapacity/(selfHeatCapacity+otherHeatCapacity));
        temperature = max(temperature - heat/selfHeatCapacity, cosmicMicrowaveBackground);
        other.temperature = max(other.temperature + heat/otherHeatCapacity, cosmicMicrowaveBackground);
        return other.temperature;
    }
    pure @nogc @safe Temperature temperatureShare(float conductionCoefficient,Temperature otherTemperature,HeatCapacity otherHeatCapacity) /// ditto
    {
        import std.math : abs;
        import std.algorithm.comparison : max;
        auto temperatureDelta=temperature-otherTemperature;
        auto selfHeatCapacity = heatCapacity;
        auto heat = conductionCoefficient*temperatureDelta*(selfHeatCapacity*otherHeatCapacity/(selfHeatCapacity+otherHeatCapacity));
        temperature = max(temperature - heat/selfHeatCapacity, cosmicMicrowaveBackground);
        otherTemperature = max(otherTemperature + heat/otherHeatCapacity, cosmicMicrowaveBackground);
        return otherTemperature;
    }
    pure @safe ReactionFlag react() /// Goes through every reaction this mixture might have and does them if they can react.
    {
        if(previousResult != ReactionFlag.REACTING && !gases.dirty)
        {
            return previousResult;
        }
        ReactionFlag result = ReactionFlag.NO_REACTION;
        import atmos.reactions : reactions;
        static foreach(reaction;reactions) // This is baked in and unrolled at compile time, so no need to mess with this
        {
            if(reaction.canReact(this))
            {
                auto thisResult = reaction.react(this);
                if(thisResult==ReactionFlag.STOP_REACTIONS)
                {
                    gases.dirty = false;
                    return ReactionFlag.STOP_REACTIONS;
                }
                else if(thisResult==ReactionFlag.REACTING)
                {
                    result = ReactionFlag.REACTING;
                }
            }
        }
        if(result == ReactionFlag.NO_REACTION)
        {
            gases.dirty = false;
        }
        return previousResult=result;
    }
    @safe string toString() /// Gives similar results to SS13 analyzer.
    {
        import std.conv : to;
        string retString = "";
        auto totalAmount = 0*mole;
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            retString ~= gas.name ~ ": " ~ to!string(amount.value(mole)) ~ " moles \n";
            totalAmount+=amount;
        }
        retString ~= "Total amount: "~to!string(totalAmount.value(mole)) ~ " moles \n";
        retString ~= "Temperature: " ~to!string(temperature.value(kelvin))~ " kelvins \n";
        return retString;
    }
}