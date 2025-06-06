#ifndef LUNASVG_SVGPARSERUTILS_H
#define LUNASVG_SVGPARSERUTILS_H

#include <cmath>
#include <string_view>
#include <limits>

namespace lunasvg {

constexpr bool IS_NUM(int cc) { return cc >= '0' && cc <= '9'; }
constexpr bool IS_ALPHA(int cc) { return (cc >= 'a' && cc <= 'z') || (cc >= 'A' && cc <= 'Z'); }
constexpr bool IS_WS(int cc) { return cc == ' ' || cc == '\t' || cc == '\n' || cc == '\r'; }

constexpr void stripLeadingSpaces(std::string_view& input)
{
    while(!input.empty() && IS_WS(input.front())) {
        input.remove_prefix(1);
    }
}

constexpr void stripTrailingSpaces(std::string_view& input)
{
    while(!input.empty() && IS_WS(input.back())) {
        input.remove_suffix(1);
    }
}

constexpr void stripLeadingAndTrailingSpaces(std::string_view& input)
{
    stripLeadingSpaces(input);
    stripTrailingSpaces(input);
}

constexpr bool skipOptionalSpaces(std::string_view& input)
{
    while(!input.empty() && IS_WS(input.front()))
        input.remove_prefix(1);
    return !input.empty();
}

constexpr bool skipOptionalSpacesOrDelimiter(std::string_view& input, char delimiter)
{
    if(!input.empty() && !IS_WS(input.front()) && delimiter != input.front())
        return false;
    if(skipOptionalSpaces(input)) {
        if(delimiter == input.front()) {
            input.remove_prefix(1);
            skipOptionalSpaces(input);
        }
    }

    return !input.empty();
}

constexpr bool skipOptionalSpacesOrComma(std::string_view& input)
{
    return skipOptionalSpacesOrDelimiter(input, ',');
}

constexpr bool skipDelimiterAndOptionalSpaces(std::string_view& input, char delimiter)
{
    if(!input.empty() && input.front() == delimiter) {
        input.remove_prefix(1);
        skipOptionalSpaces(input);
        return true;
    }

    return false;
}

constexpr bool skipDelimiter(std::string_view& input, char delimiter)
{
    if(!input.empty() && input.front() == delimiter) {
        input.remove_prefix(1);
        return true;
    }

    return false;
}

constexpr bool skipString(std::string_view& input, const std::string_view& value)
{
    if(input.size() >= value.size() && value == input.substr(0, value.size())) {
        input.remove_prefix(value.size());
        return true;
    }

    return false;
}

constexpr bool isIntegralDigit(char ch, int base)
{
    if(IS_NUM(ch))
        return ch - '0' < base;
    if(IS_ALPHA(ch))
        return (ch >= 'a' && ch < 'a' + base - 10) || (ch >= 'A' && ch < 'A' + base - 10);
    return false;
}

constexpr int toIntegralDigit(char ch)
{
    if(IS_NUM(ch))
        return ch - '0';
    if(ch >= 'a')
        return ch - 'a' + 10;
    return ch - 'A' + 10;
}

template<typename T>
inline bool parseInteger(std::string_view& input, T& integer, int base = 10)
{
    constexpr bool isSigned = std::numeric_limits<T>::is_signed;
    constexpr T intMax = std::numeric_limits<T>::max();
    const T maxMultiplier = intMax / static_cast<T>(base);

    T value = 0;
    bool isNegative = false;

    if(!input.empty() && input.front() == '+') {
        input.remove_prefix(1);
    } else if(!input.empty() && isSigned && input.front() == '-') {
        input.remove_prefix(1);
        isNegative = true;
    }

    if(input.empty() || !isIntegralDigit(input.front(), base))
        return false;
    do {
        const int digitValue = toIntegralDigit(input.front());
        if(value > maxMultiplier || (value == maxMultiplier && static_cast<T>(digitValue) > (intMax % static_cast<T>(base)) + isNegative))
            return false;
        value = static_cast<T>(base) * value + static_cast<T>(digitValue);
        input.remove_prefix(1);
    } while(!input.empty() && isIntegralDigit(input.front(), base));

    using SignedType = typename std::make_signed<T>::type;
    if(isNegative)
        integer = -static_cast<SignedType>(value);
    else
        integer = value;
    return true;
}

template<typename T>
inline bool parseNumber(std::string_view& input, T& number)
{
    constexpr T maxValue = std::numeric_limits<T>::max();
    T integer = 0;
    T fraction = 0;
    int exponent = 0;
    int sign = 1;
    int expsign = 1;

    if(!input.empty() && input.front() == '+') {
        input.remove_prefix(1);
    } else if(!input.empty() && input.front() == '-') {
        input.remove_prefix(1);
        sign = -1;
    }

    if(input.empty() || (!IS_NUM(input.front()) && input.front() != '.'))
        return false;
    if(IS_NUM(input.front())) {
        do {
            integer = static_cast<T>(10) * integer + (input.front() - '0');
            input.remove_prefix(1);
        } while(!input.empty() && IS_NUM(input.front()));
    }

    if(!input.empty() && input.front() == '.') {
        input.remove_prefix(1);
        if(input.empty() || !IS_NUM(input.front()))
            return false;
        T divisor = static_cast<T>(1);
        do {
            fraction = static_cast<T>(10) * fraction + (input.front() - '0');
            divisor *= static_cast<T>(10);
            input.remove_prefix(1);
        } while(!input.empty() && IS_NUM(input.front()));
        fraction /= divisor;
    }

    if(input.size() > 1 && (input[0] == 'e' || input[0] == 'E')
        && (input[1] != 'x' && input[1] != 'm'))
    {
        input.remove_prefix(1);
        if(!input.empty() && input.front() == '+')
            input.remove_prefix(1);
        else if(!input.empty() && input.front() == '-') {
            input.remove_prefix(1);
            expsign = -1;
        }

        if(input.empty() || !IS_NUM(input.front()))
            return false;
        do {
            exponent = 10 * exponent + (input.front() - '0');
            input.remove_prefix(1);
        } while(!input.empty() && IS_NUM(input.front()));
    }

    number = sign * (integer + fraction);
    if(exponent)
        number *= static_cast<T>(std::pow(10.0, expsign * exponent));
    return number >= -maxValue && number <= maxValue;
}

} // namespace lunasvg

#endif // LUNASVG_SVGPARSERUTILS_H
