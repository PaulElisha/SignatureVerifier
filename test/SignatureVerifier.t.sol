// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {SignatureVerifier} from "../src/SignatureVerifier.sol";
import {Test, console2} from "forge-std/Test.sol";

contract SignatureVerifierTest is Test {
    SignatureVerifier public signatureVerifier;
    Account user = makeAccount("victim");
    Account attacker = makeAccount("attacker");

    function setUp() public {
        signatureVerifier = new SignatureVerifier();

        console2.log("user address: ", user.addr);
        console2.log("contract address: ", address(signatureVerifier));
        console2.log("test address: ", address(this));
    }

    function testVerifySignatureSimple() public {
        uint256 message = 22;
        // Sign a message
        (uint8 v, bytes32 r, bytes32 s) = _signMessageSimple(message);

        // Verify the message
        bool verified = signatureVerifier.verifySignerSimple(
            message,
            v,
            r,
            s,
            user.addr
        );
        assertEq(verified, true);
    }

    function testVerifySignatureEIP191() public {
        uint256 message = 23;
        address intendedValidator = address(signatureVerifier);

        // Sign a message
        (uint8 v, bytes32 r, bytes32 s) = _signMessageEIP191(
            message,
            intendedValidator
        );

        // Verify the message
        bool verified = signatureVerifier.verifySigner191(
            message,
            v,
            r,
            s,
            user.addr
        );
        assertEq(verified, true);
    }

    function testVerifySignatureEIP712() public {
        uint256 message = 24;

        // Sign a message
        (uint8 v, bytes32 r, bytes32 s) = _signMessageEIP712(message);

        // Verify the message
        bool verified = signatureVerifier.verifySigner712(
            message,
            v,
            r,
            s,
            user.addr
        );
        assertEq(verified, true);
    }

    function testSignaturesCanBeReplayed() public {
        uint256 message = 25;

        // Sign a message
        (uint8 v, bytes32 r, bytes32 s) = _signMessageEIP712(message);

        // Verify the message
        vm.prank(address(1));
        bool verifiedOnce = signatureVerifier.verifySigner712(
            message,
            v,
            r,
            s,
            user.addr
        );
        vm.prank(address(2));
        bool verifiedTwice = signatureVerifier.verifySigner712(
            message,
            v,
            r,
            s,
            user.addr
        );

        assertEq(verifiedOnce, verifiedTwice);
        assertEq(verifiedOnce, true);
    }

    /*//////////////////////////////////////////////////////////////
                            REPLAY RESISTANT
    //////////////////////////////////////////////////////////////*/

    function testVerifySignatureReplayResistant() public {
        uint256 message = 26;

        // Sign a message
        (uint8 v, bytes32 r, bytes32 s) = _signMessageReplayResistant(message);

        SignatureVerifier.ReplayResistantMessage
            memory messageStruct = getReplayResistantMessageStruct(message);

        // Verify the message
        vm.prank(address(1));
        bool verifiedOnce = signatureVerifier.verifySignerReplayResistant(
            messageStruct,
            v,
            r,
            s,
            user.addr
        );
        assertEq(verifiedOnce, true);

        vm.prank(address(2));
        vm.expectRevert();
        signatureVerifier.verifySignerReplayResistant(
            messageStruct,
            v,
            r,
            s,
            user.addr
        );
    }

    function testIncorrectSignaturesAreNotVerified() public {
        uint256 message = 26;

        // Sign a message
        (uint8 v, bytes32 r, bytes32 s) = _signMessageReplayResistant(message);

        // make it wrong
        if (v == type(uint8).max) {
            v = v - 1;
        } else {
            v = v + 1;
        }

        SignatureVerifier.ReplayResistantMessage
            memory messageStruct = getReplayResistantMessageStruct(message);

        // Verify the message
        vm.expectRevert();
        bool verifiedOnce = signatureVerifier.verifySignerReplayResistant(
            messageStruct,
            v,
            r,
            s,
            user.addr
        );
        assertEq(verifiedOnce, false);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function _signMessageSimple(
        uint256 message
    ) internal view returns (uint8, bytes32, bytes32) {
        // Step 1. Hash the message to a bytes32
        // The value we get from hashing the message is referred to as the "digest"
        bytes32 digest = bytes32(message);

        // Step 2. Sign the message
        return vm.sign(user.key, digest);
    }

    function _signMessageEIP191(
        uint256 message,
        address intendedValidator
    ) internal view returns (uint8, bytes32, bytes32) {
        // The value we get from hashing the message is referred to as the "digest"
        // This is then the input to our signature
        bytes1 prefix = bytes1(0x19);
        bytes1 eip191Version = bytes1(0x00);
        bytes32 digest = keccak256(
            abi.encodePacked(prefix, eip191Version, intendedValidator, message)
        );
        return vm.sign(user.key, digest);
    }

    function _signMessageEIP712(
        uint256 message
    ) internal view returns (uint8, bytes32, bytes32) {
        // to encode this, we need to know the domain separator!
        bytes1 prefix = bytes1(0x19);
        bytes1 eip191Version = bytes1(0x01); // EIP-712 is version 1 of EIP-191

        bytes32 hashedMessageStruct = keccak256(
            abi.encode(
                signatureVerifier.MESSAGE_TYPEHASH(),
                SignatureVerifier.Message({number: message})
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                prefix,
                eip191Version,
                signatureVerifier.i_domain_separator(),
                hashedMessageStruct
            )
        );
        return vm.sign(user.key, digest);
    }

    uint256 public constant DEADLINE_EXTENSION = 100;

    function getReplayResistantMessageStruct(
        uint256 message
    ) public view returns (SignatureVerifier.ReplayResistantMessage memory) {
        // Find an unused nonce
        uint256 nonce = signatureVerifier.latestNonce(user.addr) + 1;

        return
            SignatureVerifier.ReplayResistantMessage({
                number: message,
                deadline: block.timestamp + DEADLINE_EXTENSION,
                nonce: nonce
            });
    }

    function _signMessageReplayResistant(
        uint256 message
    ) internal view returns (uint8, bytes32, bytes32) {
        bytes1 prefix = bytes1(0x19);
        bytes1 eip191Version = bytes1(0x01); // EIP-712 is version 1 of EIP-191

        SignatureVerifier.ReplayResistantMessage
            memory messageStruct = getReplayResistantMessageStruct(message);
        bytes32 hashedMessageStruct = keccak256(
            abi.encode(
                signatureVerifier.REPLAY_RESISTANT_MESSAGE_TYPEHASH(),
                messageStruct
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                prefix,
                eip191Version,
                signatureVerifier.i_domain_separator(),
                hashedMessageStruct
            )
        );

        return vm.sign(user.key, digest);
    }
}
