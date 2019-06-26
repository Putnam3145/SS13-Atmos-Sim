module atmos.constants;

public import quantities.compiletime, quantities.si;

enum specHeatUnit = joule/(kelvin*mole);

alias SpecificHeatCapacity = typeof(specHeatUnit); 

enum heatCapacityUnit = joule/kelvin;

alias HeatCapacity = typeof(heatCapacityUnit);

enum standardPressure = 100*kilo(pascal);
enum standardTemperature = 273.15*kelvin;
enum atmosphere = 101.325*kilo(pascal);
enum roomTemperature = 293.15*kelvin;

enum fireTemperature = 100*kelvin + standardTemperature;

enum boltzmannConstant = 1.380649*1e-23*(joule/kelvin); ///actual SI definition

enum avogadroConstant = 6.02214076*1e23*(1/mole); ///ditto

enum gasConstant=8.31446261815324*(joule/(mole*kelvin)); ///calculated using above definitions, so exact

enum cellVolume = 2500*liter;

enum openHeatTransferCoefficient = 0.4;

enum molesGasVisible = 0.25 * mole;

enum standardCellMoles = (atmosphere*cellVolume/(roomTemperature*gasConstant));

enum cosmicMicrowaveBackground = 2.7*kelvin;

enum ReactionFlag
{
    NO_REACTION,
    REACTING,
    STOP_REACTIONS
}

enum stimulumHeatScale = 100_000*kelvin;

enum fusionMoleThreshold = 250*mole;