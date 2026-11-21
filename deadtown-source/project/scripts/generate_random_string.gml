/// Candidate restored from Android ARM32. Random behavior is not verified on iOS.
var result = "";
var upper, lower, digit;
repeat (20)
{
    upper = irandom_range(65, 90);
    lower = irandom_range(97, 122);
    digit = irandom_range(48, 57);
    result += chr(choose(upper, lower, digit));
}
return result;
