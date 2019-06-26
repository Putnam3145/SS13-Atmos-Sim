module atmos.reactions;

import atmos.mix : AtmosMixture;

import atmos.gases;

import atmos.constants;

private struct GasRequirement
{
    GasDatum datum;
    AmountOfSubstance amount;
    import std.traits : isNumeric;
    int opCmp(T)(T b)
        if(is(T==GasRequirement) || isNumeric!T)
    {
        static if(is(T==GasRequirement))
        {
            auto thisValue = -datum.rarity*amount;
            auto otherValue = -b.datum.rarity*b.amount;
            if(thisValue>otherValue)
            {
                return 1;
            }
            else if(thisValue==otherValue)
            {
                return 0;
            }
            else
            {
                return -1;
            }
        }
        else static if(isNumeric!T)
        {
            auto thisValue = -datum.rarity*amount;
            if(thisValue>b)
            {
                return 1;
            }
            else if(thisValue==b)
            {
                return 0;
            }
            else
            {
                return -1;
            }
        }
    }
}

struct GasReaction(string name,
                   alias func,
                   GasRequirement[] minGasRequirements, 
                   Temperature minTempRequirement = -1*kelvin, 
                   Energy minEnerRequirement = -1*joule)
{
    //priority is hardcoded as order in the reactions enum. Yeah, yeah.
    enum gasName = name;
    import std.algorithm.sorting : sort;
    import std.algorithm.mutation : SwapStrategy;
    enum gasRequirements = minGasRequirements;
    enum tempRequirement = minTempRequirement;
    enum enerRequirement = minEnerRequirement; //we're gonna do some crazy shit with this
    pure @safe bool canReact(AtmosMixture air) const
    {
        debug import std.stdio;
        debug import std.conv;
        pragma(msg," Reaction defined: "~name);
        static if(minTempRequirement>0*kelvin)
        {
            pragma(msg,"  Requires temperature of ",minTempRequirement.value(kelvin)," kelvins.");
            if(air.temperature<minTempRequirement)
            {
                return false;
            }
        }
        static if(minEnerRequirement>0*joule)
        {
            pragma(msg,"Requires energy of ",minEnerRequirement.value(joule)," joules.");
            if(air.heatEnergy<minEnerRequirement)
            {
                return false;
            }
        }
        static if(minGasRequirements.length>0)
        {
            pragma(msg,"  Requires the following gases: ");
            static foreach(GasRequirement req; gasRequirements)
            {
                pragma(msg,"  ",req.amount.value(mole), " moles of "~req.datum.name);
                if(air[req.datum]<req.amount)
                {
                    return false;
                }
            }
        }
        return true;
    }
    pure @safe ReactionFlag react(ref AtmosMixture air) inout
    {
        import std.traits : isFunction,fullyQualifiedName;
        static if(isFunction!func)
        {
            pragma(msg,"  Has a special function: ",fullyQualifiedName!func);
            return func(air);
        }
        else
        {
            pragma(msg,"  Has no special function. Why does this exist?");
            return ReactionFlag.NO_REACTION;
        }
    }
}

pure nothrow @nogc @safe private ReactionFlag nobliumSuppress(ref AtmosMixture air)
{
    return ReactionFlag.STOP_REACTIONS;
}

pure nothrow @nogc @safe private ReactionFlag waterVapor(ref AtmosMixture air)
{
    return ReactionFlag.NO_REACTION;
}

pure @safe private ReactionFlag tritFire(ref AtmosMixture air) /// note: based on yogs rather than on tg due to conservation of mass
{
    enum minimumOxyBurnEnergy = 2_000_000 * joule;
    enum tritiumBurnOxyFactor = 100;
    enum tritiumBurnTritFactor = 10;
    enum fireHydrogenEnergyReleased = 560 * kilo(joule)/mole;
    auto energyReleased = 0 * joule;
	auto burnedFuel = 0 * mole;
	auto initialTrit = air[getGas!"tritium"];
    auto oldEnergy = air.thermalEnergy;
    if(air[getGas!"o2"]<initialTrit || oldEnergy<=minimumOxyBurnEnergy)
    {
        burnedFuel = air[getGas!"o2"]/tritiumBurnOxyFactor;
        if(burnedFuel>initialTrit) burnedFuel = initialTrit; //prevents negative mole values of trit
        air[getGas!"tritium"] -= burnedFuel;
    }
    else
    {
        burnedFuel = initialTrit;
        air[getGas!"tritium"] *= (1.0 - 1.0/tritiumBurnTritFactor);
        air[getGas!"o2"] -= air[getGas!"tritium"];
        energyReleased += fireHydrogenEnergyReleased * burnedFuel * (tritiumBurnTritFactor - 1);
    }
    if(burnedFuel>0*mole)
    {
        energyReleased += fireHydrogenEnergyReleased * burnedFuel;
        //radiation here
        air[getGas!"water_vapor"] += burnedFuel; //assertion is automatic
    }
    if(energyReleased>0*joule)
    {
        air.temperature = (oldEnergy+energyReleased)/air.heatCapacity;
    }
    return ReactionFlag.REACTING;
}

pure @safe private ReactionFlag plasFire(ref AtmosMixture air)
{
    enum plasmaUpperTemperature = 1370*kelvin+standardTemperature;
    enum oxygenBurnRateBase = 1.4;
    enum superSaturationThreshold = 96;
    enum plasmaOxygenFullburn = 10;
    enum plasmaBurnRateDelta = 9;
    enum firePlasmaEnergyReleased = 3 * mega(joule)/mole;
    bool superSaturation = false;
    real temperatureScale;
    AmountOfSubstance plasmaBurnRate;
    real oxygenBurnRate;
    auto oldEnergy = air.thermalEnergy;
    Energy energyReleased;
    if(air.temperature>plasmaUpperTemperature)
    {
        temperatureScale = 1;
    }
    else
    {
        temperatureScale = (air.temperature-fireTemperature)/(plasmaUpperTemperature-fireTemperature);
    }
    if(temperatureScale > 0)
    {
        oxygenBurnRate = (oxygenBurnRateBase-temperatureScale);
        superSaturation = (air[getGas!"o2"]/air[getGas!"plasma"]>superSaturationThreshold);
        if(air[getGas!"o2"]>air[getGas!"plasma"]*plasmaOxygenFullburn)
        {
            plasmaBurnRate = air[getGas!"plasma"]*temperatureScale/plasmaBurnRateDelta;
        }
        else
        {
            plasmaBurnRate = (temperatureScale*(air[getGas!"o2"]/plasmaOxygenFullburn))/plasmaBurnRateDelta;
        }
        import std.algorithm : min;
        plasmaBurnRate = min(plasmaBurnRate.value(mole),air[getGas!"plasma"].value(mole),air[getGas!"o2"].value(mole)/oxygenBurnRate)*mole;
        air[getGas!"plasma"] -= plasmaBurnRate;
        air[getGas!"o2"] -= (plasmaBurnRate*oxygenBurnRate);
        if(superSaturation)
        {
            air[getGas!"tritium"]+=plasmaBurnRate;
        }
        else
        {
            air[getGas!"co2"]+=plasmaBurnRate;
        }
        energyReleased = firePlasmaEnergyReleased * plasmaBurnRate;
        bool reacted = plasmaBurnRate*(1+oxygenBurnRate)>0*mole;
        if(energyReleased > 0*joule)
        {
            air.temperature = (oldEnergy+energyReleased)/air.heatCapacity;
        }
        if(reacted)
        {
            return ReactionFlag.REACTING;
        }
    }
    return ReactionFlag.NO_REACTION;
}

pure @safe private ReactionFlag dryHeatSterilization(ref AtmosMixture air)
{
    if(air[getGas!"water_vapor"]/air.totalMoles>0.1)
    {
        return ReactionFlag.NO_REACTION; //has to be dry
    }
    import std.algorithm : min;
    auto cleanedAir=min(air[getGas!"miasma"].value(mole),
    20 + (air.temperature.value(kelvin) - fireTemperature.value(kelvin) - 70) / 20) * mole;
    air[getGas!"miasma"] -= cleanedAir;
    air[getGas!"o2"] += cleanedAir;
    air.temperature += cleanedAir * (0.002*(kelvin/mole));
    return ReactionFlag.REACTING;
    //add 160 research points per mole--probably add a global research point system to keep track for funsies?
}

pure @safe private ReactionFlag nobliumFormation(ref AtmosMixture air)
{
    enum nobliumFormationEnergy = 2e9 * (joule/mole);
    auto oldEnergy = air.thermalEnergy;
    import std.algorithm : min,max;
    auto nobFormed = min((air[getGas!"n2"]+air[getGas!"tritium"]/100).value(mole),(air[getGas!"tritium"]/10).value(mole),(air[getGas!"n2"]/20).value(mole)) * mole;
    Energy energyTaken = (nobFormed * nobliumFormationEnergy) / max(air[getGas!"bz"].value(mole),1);
	if ((air[getGas!"tritium"] < 10*nobFormed) || (air[getGas!"n2"] < 20*nobFormed))
    {
        return ReactionFlag.NO_REACTION;
    }
	air[getGas!"tritium"] -= 10*nobFormed;
	air[getGas!"n2"] -= 20*nobFormed;
	air[getGas!"nob"] += nobFormed;
	//SSresearch.science_tech.add_point_type(TECHWEB_POINT_TYPE_DEFAULT, nob_formed*NOBLIUM_RESEARCH_AMOUNT)
    if(energyTaken != 0*joule)
    {
        air.temperature = (oldEnergy-energyTaken)/air.heatCapacity;
    }
    return ReactionFlag.REACTING;
}

pure @safe private ReactionFlag stimFormation(ref AtmosMixture air)
{
    enum stimulumFirstRise = 0.65 / joule;
    enum stimulumFirstDrop = 0.065 / square(joule);
    enum stimulumSecondRise = 0.0009 / cubic(joule);
    enum stimulumAbsoluteDrop = 0.00000335 / (square(joule)*square(joule));
    import std.algorithm : min;
    const auto oldEnergy = air.thermalEnergy;
    const Energy heatScale = min(air.temperature/stimulumHeatScale,air[getGas!"tritium"].value(mole),air[getGas!"plasma"].value(mole),air[getGas!"no2"].value(mole)) * joule;
    const Energy stimEnergyChange = heatScale + stimulumFirstRise*(heatScale.pow!2) - stimulumFirstDrop*(heatScale.pow!3) + stimulumSecondRise*(heatScale.pow!4) - stimulumAbsoluteDrop*(heatScale.pow!5);
    if ((air[getGas!"tritium"].value(mole) - heatScale.value(joule) < 0 )|| (air[getGas!"plasma"].value(mole) - heatScale.value(joule) < 0 ) || (air[getGas!"no2"].value(mole) - heatScale.value(joule) < 0 )) //these ifs are bad
    {
        return ReactionFlag.NO_REACTION;
    }
    const AmountOfSubstance moleChange = heatScale*(mole/joule); //stop making me do things like this. come up with real constants
	air[getGas!"stim"] += moleChange/10;
	air[getGas!"tritium"] -= moleChange;
	air[getGas!"plasma"] -= moleChange;
    air[getGas!"no2"] -= moleChange;
    //add science points, 50/joule
    if(stimEnergyChange != 0*joule)
    {
        air.temperature = (oldEnergy+stimEnergyChange)/air.heatCapacity;
    }
    return ReactionFlag.REACTING;
}

pure @safe private ReactionFlag bzFormation(ref AtmosMixture air)
{
    enum fireCarbonEnergyReleased = 100 * (kilo(joule)/mole);
    const auto oldEnergy = air.thermalEnergy;
    const auto oldPressure = air.pressure;
    import std.algorithm : min,max;
    const AmountOfSubstance reactionEfficiency = min(1/((oldPressure/(0.1*atmosphere))*(max(air[getGas!"plasma"]/air[getGas!"n2o"],1))),air[getGas!"n2o"].value(mole),air[getGas!"plasma"].value(mole)/2) * mole;
    const Energy energyReleased = 2*reactionEfficiency*fireCarbonEnergyReleased;
    if ((air[getGas!"n2o"] < reactionEfficiency )|| (air[getGas!"plasma"] < (2*reactionEfficiency)) || energyReleased <= 0 * joule) //Shouldn't produce gas from nothing.
    {
        return ReactionFlag.NO_REACTION;
    }
    air[getGas!"bz"] += reactionEfficiency;
    if(reactionEfficiency == air[getGas!"n2o"])
    {
        auto nitrousBalanceChange = min(oldPressure.value(kilo(pascal)),1)*mole;
        air[getGas!"bz"] -= nitrousBalanceChange;
        air[getGas!"o2"] += nitrousBalanceChange;
    }
	air[getGas!"n2o"] -= reactionEfficiency;
	air[getGas!"plasma"]  -= 2*reactionEfficiency;
    //SSresearch.science_tech.add_point_type(TECHWEB_POINT_TYPE_DEFAULT, min((reaction_efficency**2)*BZ_RESEARCH_SCALE),BZ_RESEARCH_MAX_AMOUNT)
    //we already returned if energyReleased is non-positive
    air.temperature = (oldEnergy+energyReleased)/air.heatCapacity;
    return ReactionFlag.REACTING;
}

pure @safe private ReactionFlag nitrylFormation(ref AtmosMixture air)
{
    enum nitrylFormationEnergy = 100000 * (joule/mole);
    import std.algorithm : min; //why am doing this each function? i dunno, feels better
    const auto oldEnergy = air.thermalEnergy;
	const auto reactionEfficiency = min(air.temperature/(fireTemperature*100),air[getGas!"o2"].value(mole),air[getGas!"n2"].value(mole))*mole;
	const auto energyUsed = reactionEfficiency*nitrylFormationEnergy;
    if ((air[getGas!"o2"] < reactionEfficiency )|| (air[getGas!"n2"] < (reactionEfficiency))) //Shouldn't produce gas from nothing.
    {
        return ReactionFlag.NO_REACTION;
    }
	air[getGas!"o2"] -= reactionEfficiency;
	air[getGas!"n2"] -= reactionEfficiency;
	air[getGas!"no2"] += reactionEfficiency*2;
    air.temperature = (oldEnergy-energyUsed)/air.heatCapacity;
    return ReactionFlag.REACTING;
}

pure @safe private ReactionFlag fusion(ref AtmosMixture air)
{
    enum toroidVolumeBreakeven = kilo(liter);
    enum instabilityGasFactor = 0.003;
    enum plasmaBindingEnergy = 20*(mega(joule)/mole);
    enum fusionTritiumMolesUsed = 1*mole;
    enum fusionInstabilityEndothermality = 2;
    enum fusionTritiumConversionCoefficient = 1e-10/joule;
    import std.math; //YEAH ALL OF IT
    Energy reactionEnergy = 0 * joule;
    const auto initialPlasma = air[getGas!"plasma"];
    const auto initialCarbon = air[getGas!"co2"];
    assert(initialPlasma>=fusionMoleThreshold,"Plasma in fusion somehow less than requirement!");
    assert(initialCarbon>=fusionMoleThreshold,"CO2 in fusion somehow less than requirement!");
    const auto scaleFactor = (air.volume / PI).value(liter);
    //The size of the phase space hypertorus
    const auto toroidalSize = (3*PI)+atan((air.volume-toroidVolumeBreakeven)/toroidVolumeBreakeven);
    //3*PI above rather than 2*PI because atan can return -pi
    real gasPower = 0.0; // uh??
    foreach(GasDatum gas,AmountOfSubstance amount;air.gases)
    {
        gasPower+=gas.fusionPower*amount.value(mole);
    }
    const auto instability = pow(gasPower*instabilityGasFactor,2)%toroidalSize;
    auto plasma = (initialPlasma - fusionMoleThreshold) / scaleFactor;
    auto carbon = (initialCarbon - fusionMoleThreshold) / scaleFactor;
    assert(plasma>0*mole,"Plasma is somehow negative after scaling!");
    assert(carbon>0*mole,"Plasma is somehow negative after scaling!");
	plasma = abs((plasma.value(mole) - (instability*(sin(carbon.value(mole))))%toroidalSize)) * mole;
    //count the rings. ss13's modulus is positive, this ain't, who knew
	carbon = abs((carbon - plasma).value(mole)%toroidalSize)*mole;
    air[getGas!"plasma"] = plasma*scaleFactor + fusionMoleThreshold;
    air[getGas!"co2"] = carbon*scaleFactor + fusionMoleThreshold;
    const auto deltaPlasma = initialPlasma - air[getGas!"plasma"];
    reactionEnergy += deltaPlasma*plasmaBindingEnergy;
    if(instability < fusionInstabilityEndothermality)
    {
        import std.algorithm : max;
        reactionEnergy = max(0,reactionEnergy.value(joule))*joule;
    }
    else if(reactionEnergy < 0*joule)
    {
        reactionEnergy *= sqrt(instability-fusionInstabilityEndothermality);
    }
    if((air.thermalEnergy + reactionEnergy) < 0*joule)
    {
        air[getGas!"plasma"] = initialPlasma;
        air[getGas!"co2"] = initialCarbon;
        return ReactionFlag.NO_REACTION;
    }
    air[getGas!"tritium"] -= fusionTritiumMolesUsed;
    if(reactionEnergy > 0*joule)
    {
        air[getGas!"o2"] += fusionTritiumMolesUsed*(reactionEnergy*fusionTritiumConversionCoefficient);
		air[getGas!"n2o"] += fusionTritiumMolesUsed*(reactionEnergy*fusionTritiumConversionCoefficient);
    }
    else
    {
        air[getGas!"bz"] += fusionTritiumMolesUsed*(reactionEnergy*-fusionTritiumConversionCoefficient);
		air[getGas!"no2"] += fusionTritiumMolesUsed*(reactionEnergy*-fusionTritiumConversionCoefficient);
    }
    if(reactionEnergy != 0*joule)
    {
        //radiation, particles here
        air.temperature = (air.thermalEnergy+reactionEnergy)/air.heatCapacity;
        return ReactionFlag.REACTING;
    }
    return ReactionFlag.NO_REACTION;
}



pragma(msg,"Defining reactions.");

import std.traits : moduleName;

@("reaction") enum hypernob = GasReaction!("Hyper-Noblium Reaction Suppression",
                            nobliumSuppress,
                            [GasRequirement(getGas!"nob",5*mole)])();
@("reaction") enum nobliumformation = GasReaction!("Hyper-Noblium condensation",
                            nobliumFormation,
                            [GasRequirement(getGas!"n2",10*mole),
                             GasRequirement(getGas!"tritium",5*mole)],
                             5_000_000*kelvin)();
@("reaction") enum stimformation = GasReaction!("Stimulum formation",
                            stimFormation,
                            [GasRequirement(getGas!"plasma",10*mole),
                             GasRequirement(getGas!"tritium",30*mole),
                             GasRequirement(getGas!"bz",20*mole),
                             GasRequirement(getGas!"no2",20*mole)],
                            stimulumHeatScale/2)();
@("reaction") enum bzformation = GasReaction!("BZ Gas formation",
                            bzFormation,
                            [GasRequirement(getGas!"plasma",10*mole),
                             GasRequirement(getGas!"n2o",10*mole)])();
@("reaction") enum nitrylformation = GasReaction!("Nitryl formation",
                            nitrylFormation,
                            [GasRequirement(getGas!"n2",20*mole),
                             GasRequirement(getGas!"o2",20*mole),
                             GasRequirement(getGas!"n2o",5*mole)],
                            fireTemperature*60)();
@("reaction") enum fus = GasReaction!("Plasmic Fusion",
                            fusion,
                            [GasRequirement(getGas!"plasma",fusionMoleThreshold),
                             GasRequirement(getGas!"co2",fusionMoleThreshold),
                             GasRequirement(getGas!"tritium",1*mole)],
                            10000*kelvin)();
@("reaction") enum vapor = GasReaction!("Water Vapor",
                            waterVapor,
                            [GasRequirement(getGas!"water_vapor",0.25*mole)])();
@("reaction") enum tritfire = GasReaction!("Tritium Combustion",
                            tritFire,
                            [GasRequirement(getGas!"tritium",0.01*mole),
                             GasRequirement(getGas!"o2",0.01*mole)],
                             fireTemperature)();
@("reaction") enum plasfire = GasReaction!("Plasma Combustion",
                            plasFire,
                            [GasRequirement(getGas!"plasma",0.01*mole),
                             GasRequirement(getGas!"o2",0.01*mole)],
                             fireTemperature)();
@("reaction") enum miaster = GasReaction!("Dry Heat Sterilization",
                            dryHeatSterilization,
                            [GasRequirement(getGas!"miasma",0.01*mole)],
                            fireTemperature+70*kelvin)();

import std.traits;

alias reactions = getSymbolsByUDA!(atmos.reactions,"reaction");

//not sure what use this stuff will ever have, but hey, it's cool i guess

template reactionHasGas(GasDatum gas)
{
    bool reactionHasGas(alias reaction)() //this shit works??
    {
        bool returnBool = false;
        static foreach(req;reaction.gasRequirements)
        {
            static if(req.datum==gas)
            {
                returnBool = true; //this prevents some spurious compile warnings, it's all compile-time anyway
            }
        }
        return returnBool;
    }
}

import std.meta : Filter, templateAnd;

alias reactionsOfGas(gas) = Filter!(reactionHasGas!gas,reactions);

alias reactionsOfGases(gases...) = Filter!(templateAnd!(staticMap!(reactionHasGas,gases)),reactions);

template reactionHasOnlyGases(gases...)
{
    bool reactionHasOnlyGases(alias reaction)()
    {
        int matches = 0;
        static foreach(req;reaction.gasRequirements)
        {
            static foreach(gas;gases)
            {
                static if(req.datum==gas)
                {
                    matches+=1;
                }
                else
                {
                    matches+=100;
                }
            }
        }
        return matches==gases.length;
    }
}

alias reactionsOfOnlyGases(gases...) = Filter!(reactionHasOnlyGases!gases,reactions);

unittest
{
    import std.conv : to;
    import std.stdio : writeln;
    import std.math : approxEqual;
    auto tritiumTestMix = AtmosMixture();
    tritiumTestMix[getGas!"tritium"]=250*mole;
    assert(tritiumTestMix[getGas!"tritium"]>0*mole,"Gas amounts not assigning correctly!");
    tritiumTestMix[getGas!"o2"]=250*mole;
    tritiumTestMix.temperature=10000*kelvin;
    auto result = tritiumTestMix.react();
    assert(result==ReactionFlag.REACTING,"result incorrect! "~ to!string(result) ~ " instead of REACTING");
    assert(approxEqual(tritiumTestMix.temperature.value(kelvin),115686),"tritium temp wrong!");
    assert(tritiumTestMix[getGas!"o2"]==25*mole,"oxygen content wrong!");
    assert(tritiumTestMix[getGas!"water_vapor"]==250*mole,"h2o content wrong!");
    assert(tritiumTestMix[getGas!"tritium"]==225*mole,"tritium content wrong!");
    assert(tritiumTestMix.totalMoles==500*mole,"mole total wrong!");
    assert(approxEqual(tritiumTestMix.pressure.value(kilo(pascal)),192271),"pressure wrong!");
    result = tritiumTestMix.react();
    assert(result==ReactionFlag.REACTING,"result incorrect! "~ to!string(result) ~ " instead of REACTING 2");
    assert(approxEqual(tritiumTestMix.temperature.value(kelvin),115629),"tritium temp wrong! 2");
    assert(tritiumTestMix[getGas!"o2"]==25*mole,"oxygen content wrong! 2");
    assert(tritiumTestMix[getGas!"water_vapor"]==250.25*mole,"h2o content wrong! 2");
    assert(tritiumTestMix[getGas!"tritium"]==224.75*mole,"tritium content wrong! 2");
    assert(tritiumTestMix.totalMoles==500*mole,"mole total wrong! 2");
    assert(tritiumTestMix.pressure.value(kilo(pascal)).approxEqual(192176),"pressure wrong! 2");
    auto plasmaTestMixOne = AtmosMixture();
    plasmaTestMixOne[getGas!"plasma"] = 250*mole;
    plasmaTestMixOne[getGas!"o2"]=250*mole;
    plasmaTestMixOne.temperature = 1000*kelvin;
    result = plasmaTestMixOne.react();
    assert(result==ReactionFlag.REACTING,"result incorrect! "~ to!string(result) ~ " instead of REACTING");
    assert(approxEqual(plasmaTestMixOne.temperature.value(kelvin),1079.85),"plasma temp wrong!");
    assert(approxEqual(plasmaTestMixOne[getGas!"o2"].value(mole),248.757),"oxygen content wrong!");
    assert(approxEqual(plasmaTestMixOne[getGas!"plasma"].value(mole),248.629),"plasma content wrong!");
    assert(approxEqual(plasmaTestMixOne[getGas!"co2"].value(mole),1.37106),"carbon dioxide wrong!");
    assert(approxEqual(plasmaTestMixOne.totalMoles.value(mole),498.757),"mole total wrong!");
    assert(approxEqual(plasmaTestMixOne.pressure.value(kilo(pascal)),1790.25),"pressure wrong!");
    //tritium burn testing
    auto plasmaTestMixTwo = AtmosMixture();
    plasmaTestMixTwo[getGas!"plasma"] = 1*mole;
    plasmaTestMixTwo[getGas!"o2"]=97*mole;
    plasmaTestMixTwo.temperature = 1000*kelvin;
    result = plasmaTestMixTwo.react();
    assert(result==ReactionFlag.REACTING,"result incorrect! "~ to!string(result) ~ " instead of REACTING");
    assert(approxEqual(plasmaTestMixTwo.temperature.value(kelvin),1082.66),"trit prod temp wrong!");
    assert(approxEqual(plasmaTestMixTwo[getGas!"o2"].value(mole),96.9503),"oxygen content wrong!");
    assert(approxEqual(plasmaTestMixTwo[getGas!"plasma"].value(mole),0.945158),"plasma content wrong!");
    assert(approxEqual(plasmaTestMixTwo[getGas!"tritium"].value(mole),0.0548425),"tritium content wrong!");
    assert(approxEqual(plasmaTestMixTwo.totalMoles.value(mole),97.9503),"mole total wrong!");
    assert(approxEqual(plasmaTestMixTwo.pressure.value(kilo(pascal)),352.499),"pressure wrong!");
}