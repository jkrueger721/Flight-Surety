pragma solidity >=0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./FlightSuretyApp.sol";
contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    uint256 private authorizedAirlineCount = 0;
    uint256 private changeOperatingStatusVotes = 0;
    address private insuranceAccount;
    uint256 private insuranceBalance = 0;


    struct Flight {
        uint8 statusCode;
        uint256 updatedTimestamp;        
        Airline airline;
    }
    struct Airline { 
        string name;
        address account;
        bool isRegistered;
        bool isAuthorized;
        bool operationalVote;
        

    }
    struct Insuree{
        address account;
        uint256 insuranceAmount;
        uint256 payoutBalance;

    }
    mapping(address => uint256) private funding;
    mapping(bytes32 => Flight) private flights;
    mapping(address => Airline) airlines; 
    mapping(address => Insuree)private insurees; 
    mapping(address => uint256) private creditBalance;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/
    event RegiteredAirline(address airline);
    event AuthorizedAirline(address airline);
    event BoughtInsurence(address caller, bytes32 key,uint256 amount);
    event CreditInsuree(address airline, address insuree, uint256 amount);
    event PayInsuree(address airline, address insuree, uint256 amount);


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor()public 
    {
        contractOwner = msg.sender;

         airlines[contractOwner] = Airline({
                    name: "Default Name",
                    account: contractOwner,
                    isRegistered: true,
                    isAuthorized: true,
                    operationalVote: true

                    });

        authorizedAirlineCount = authorizedAirlineCount.add(1);
        emit RegiteredAirline(contractOwner);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in 
    *      the event there is an issue that needs to be fixed
    */

    modifier requireIsAuthorized()
    {
        require(airlines[msg.sender].isAuthorized, "Airline needs to be authorized");
        _;
    }
    modifier requireIsOperational() 
    {
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner ");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */      
    function isOperational() 
                            public 
                            view 
                            returns(bool) 
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */    
      function setOperatingStatus
                            (
                                bool mode,
                                address caller
                            )
                            external

                            requireContractOwner


    {
        require(operational == airlines[caller].operationalVote, "Duplicate caller");
        require(mode!=operational, "New mode must be different from existing mode");


        if (authorizedAirlineCount < 4) {
          operational = mode;
        } else { //use multi-party consensus amount authorized airlines to reach 50% aggreement
          changeOperatingStatusVotes = changeOperatingStatusVotes.add(1);
          airlines[caller].operationalVote = mode;
          if (changeOperatingStatusVotes >= (authorizedAirlineCount.div(2))) {
            operational = mode;
            changeOperatingStatusVotes = authorizedAirlineCount - changeOperatingStatusVotes;
          }
        }

    }
    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */   
    function registerAirline
                            (   string name,
                                address airline
                            )
                            requireIsOperational
                            
                            external
                            
    {

        require(!airlines[airline].isRegistered,"airline cant already be registered");

        if(authorizedAirlineCount <= 4){
          airlines[airline] = Airline({
                      name: name,
                      account: airline,
                      isRegistered: true,
                      isAuthorized: false,
                      operationalVote: true
                      });
         authorizedAirlineCount = authorizedAirlineCount.add(1);
        }

        
        emit RegiteredAirline(airline);
    }

    function isAirline(address airline)public returns (bool)
    {
        return airlines[airline].isRegistered;
    }
   /**
    * @dev Buy insurance for a flight
    *
    */   
    function buy
                            (   address airline,     
                                address insuree, 
                                string flight,
                                uint256 timeStamp,
                                uint256 amount

                            )
                            requireIsOperational
                            external
                            payable
    {
        require(insurees[insuree].account == insuree,"need to provide insuree account address");
        require(msg.sender == insuree, "insuree calls this function");
        require(amount == msg.value,"amount must equal value sent");

        bytes32 key = getFlightKey(airline, flight, timeStamp);
        airline.transfer(amount);
        insurees[insuree].insuranceAmount += amount;
        insuranceBalance += amount;

        emit BoughtInsurence(msg.sender, key, amount);
    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                (
                                   address airline,
                                   address insuree,
                                   uint256 creditAmount
                                )
                                requireIsOperational
                                external
                                
                               
    {
        require(insurees[insuree].insuranceAmount >= creditAmount);

        insurees[insuree].payoutBalance = creditAmount; 
        emit CreditInsuree(airline,insuree,creditAmount);
    }
    

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (   
                                   address airline,
                                   address insuree,
                                   uint256 payoutAmount
                            )
                            requireIsOperational
                            external
                        
    {
        require(msg.sender == airline);
        insurees[insuree].account.transfer(payoutAmount);
        emit PayInsuree(airline, insuree, payoutAmount);
    }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */   
     function fund
                            (
                              address airline
                            )
                            public
                            payable
                            requireIsOperational

    {
        require(msg.value >= 10 ether, "Inadaquate funds");
        require(airlines[airline].isRegistered, "Sending account must be registered before it can be funded");


        uint256 totalAmount = totalAmount.add(msg.value);
        airline.transfer(msg.value); //their code has the totalAmount being transferred to the contract account. Why?

        if (!airlines[airline].isAuthorized) {
            airlines[airline].isAuthorized = true;
            authorizedAirlineCount = authorizedAirlineCount.add(1);
            emit AuthorizedAirline(airline);
        }


    }
    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32) 
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function() 
                            external 
                            payable 
    {
        fund(msg.sender);
    }


}

