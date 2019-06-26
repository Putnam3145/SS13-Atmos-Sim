module atmos.mix;

import atmos;

/** 
    Can be treated as a AmountOfSubstance[GasDatum] for all intents and purposes, but automatically asserts gases.
    It should be noted that iteration over the whole list is no slower for this.
*/
struct GasEntries 
{
    AmountOfSubstance[GasDatum] gases;
    bool dirty = true;
    alias gases this;
    pure @safe AmountOfSubstance opIndex(GasDatum gas)
    {
        return gases.get(gas,0*mole);
    }
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
	GasEntries gases;
    alias gases this;
    Temperature temperature = 0*kelvin;
    Volume volume = cellVolume;
    AmountOfSubstance lastShare = 0*mole;
    ReactionFlag previousResult = ReactionFlag.NO_REACTION;
    this(Volume newVolume)
    {
        volume=newVolume;
    }
    this(float newVolume)
    {
        this(newVolume*liter);
    }
    pure @nogc @safe HeatCapacity heatCapacity()
    {
        HeatCapacity totalAmount=0*heatCapacityUnit;
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            totalAmount+=gas.heatCapacity(amount);
        }
        return totalAmount;
    }
    pure @nogc @safe AmountOfSubstance totalMoles()
    {
        AmountOfSubstance totalAmount = 0*mole;
        foreach(GasDatum gas,AmountOfSubstance amount;gases)
        {
            totalAmount+=amount;
        }
        return totalAmount;
    }
    pure @nogc @safe Pressure pressure()
    in
    {
        assert(volume>0*liter); //no division by zero
    }
    do
    {
        return (gasConstant*totalMoles*temperature)/volume;
    }
    pure @nogc @safe Energy thermalEnergy()
    {
        return heatCapacity*temperature;
    }
    pure @safe void merge(AtmosMixture other)
    {
        temperature = (thermalEnergy + other.thermalEnergy) / (heatCapacity + other.heatCapacity);
        foreach(GasDatum gas,AmountOfSubstance amount;other.gases)
        {
            this.gases[gas]+=amount;
        }
    }
    pure @safe AtmosMixture remove(AmountOfSubstance amount)
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
    pure @safe AtmosMixture removeRatio(float ratio)
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
    pure @safe Pressure share(AtmosMixture other, int adjacentTurfs = 4) //none of you are free of sin
    {
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
    pure @nogc @safe Temperature temperatureShare(AtmosMixture other,float conductionCoefficient)
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
    pure @nogc @safe Temperature temperatureShare(float conductionCoefficient,Temperature otherTemperature,HeatCapacity otherHeatCapacity)
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
    pure @safe ReactionFlag react()
    {
        if(previousResult != ReactionFlag.REACTING && !gases.dirty)
        {
            return previousResult;
        }
        ReactionFlag result = ReactionFlag.NO_REACTION;
        import atmos.reactions : reactions;
        static foreach(reaction;reactions)
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
    @safe string toString()
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