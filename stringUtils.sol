// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library stringUtils {
    function isNumber(bytes1 b) private pure returns (bool) {
        return b >= 0x30 && b <= 0x39;
    }

    function isLetter(bytes1 b) private pure returns (bool) {
        return (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A);
    }

    function substring(
        string memory str,
        uint256 startIndex,
        uint256 endIndex
    ) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint256 i = 0; i < result.length; i++) {
            result[i] = strBytes[startIndex + i];
        }
        return string(result);
    }

    function splitString(string memory input)
        internal
        pure
        returns (
            string memory,
            string memory,
            string memory,
            string memory
        )
    {
        bytes memory inputBytes = bytes(input);
        uint256[3] memory splitIndices;
        uint256 splitCount = 0;

        for (uint256 i = 0; i < inputBytes.length && splitCount < 3; i++) {
            if (isNumber(inputBytes[i])) {
                while (i < inputBytes.length && isNumber(inputBytes[i])) i++;
                splitIndices[splitCount++] = i;
            }
        }
        return (
            substring(input, 0, splitIndices[0]),
            substring(input, splitIndices[0], splitIndices[1]),
            substring(input, splitIndices[1], splitIndices[2]),
            substring(input, splitIndices[2], inputBytes.length)
        );
    }

    function extractNoNumbers(string memory input)
        private
        pure
        returns (string memory)
    {
        bytes memory inputBytes = bytes(input);
        bytes memory result = new bytes(28);
        uint256 resultIndex = 0;
        for (uint256 i = 0; i < inputBytes.length && resultIndex < 28; i++) {
            if (!isNumber(inputBytes[i])) result[resultIndex++] = inputBytes[i];
        }
        return string(result);
    }

    function processString(string memory input)
        internal
        pure
        returns (
            string memory,
            string memory,
            string memory,
            string memory,
            string memory
        )
    {
        string memory noNumbers = extractNoNumbers(input);
        (
            string memory part1,
            string memory part2,
            string memory part3,
            string memory part4
        ) = splitString(input);
        return (noNumbers, part1, part2, part3, part4);
    }

    function uintToString(uint256 number) private pure returns (string memory) {
        if (number == 0) return "0";
        uint256 digits = 0;
        uint256 temp = number;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (number != 0) {
            buffer[--digits] = bytes1(uint8(48 + (number % 10)));
            number /= 10;
        }
        return string(buffer);
    }

    function formatWithXIO(uint256 number)
        internal
        pure
        returns (string memory)
    {
        require(number <= 99999999, "Number must be 8 digits or less");
        string memory numberStr = uintToString(number);
        uint256 leadingZeros = 8 - bytes(numberStr).length;
        bytes memory result = new bytes(11);
        result[0] = "x";
        result[1] = "i";
        result[2] = "o";
        for (uint256 i = 0; i < leadingZeros; i++) result[3 + i] = "0";
        for (uint256 i = 0; i < bytes(numberStr).length; i++)
            result[3 + leadingZeros + i] = bytes(numberStr)[i];
        return string(result);
    }

    function isTraitValid(string memory trait, bytes2 prefix)
        private
        pure
        returns (bool)
    {
        bytes memory b = bytes(trait);
        if (b.length <= 7 || b[0] != prefix[0] || b[1] != prefix[1])
            return false;
        for (uint256 i = 0; i < 7; i++) if (!isLetter(b[i])) return false;
        for (uint256 i = 7; i < b.length; i++)
            if (!isNumber(b[i])) return false;
        return true;
    }

    function isStrapValid(string memory strap) internal pure returns (bool) {
        return isTraitValid(strap, "aa");
    }

    function isDialValid(string memory dial) internal pure returns (bool) {
        return isTraitValid(dial, "ab");
    }

    function isItemValid(string memory item) internal pure returns (bool) {
        return isTraitValid(item, "ac");
    }

    function isHologramValid(string memory hologram)
        internal
        pure
        returns (bool)
    {
        return isTraitValid(hologram, "ad");
    }

    function isDnaValid(string memory dna) internal pure returns (bool) {
        bytes memory dnaBytes = bytes(dna);
        if (dnaBytes.length < 28) return false;

        uint256 index = 0;
        for (uint256 blockIndex = 0; blockIndex < 4; blockIndex++) {
            for (uint256 i = 0; i < 7; i++) {
                if (index >= dnaBytes.length || !isLetter(dnaBytes[index++]))
                    return false;
            }

            uint256 numStart = index;
            while (index < dnaBytes.length && isNumber(dnaBytes[index]))
                index++;
            if (index == numStart) return false;
        }

        return index == dnaBytes.length;
    }

    function sliceString(
        string memory str,
        uint256 start,
        uint256 length
    ) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        require(start + length <= strBytes.length, "Slice out of bounds");
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = strBytes[start + i];
        }
        return string(result);
    }

    function concatenateTrails(
        string memory a,
        string memory b,
        string memory c,
        string memory d
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    sliceString(a, 0, 7),
                    sliceString(b, 0, 7),
                    sliceString(c, 0, 7),
                    sliceString(d, 0, 7)
                )
            );
    }

    function generateFullDNA(
        string memory strap,
        string memory dial,
        string memory item,
        string memory hologram
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(strap, dial, item, hologram));
    }

    function normalizeTrait(string memory trait)
        internal
        pure
        returns (string memory)
    {
        bytes memory input = bytes(trait);
        require(input.length >= 7, "Trait too short to normalize");
        bytes memory result = new bytes(7);
        for (uint256 i = 0; i < 7; i++) {
            result[i] = input[i];
        }
        return string(result);
    }
}