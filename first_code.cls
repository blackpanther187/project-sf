public class first_code {
public with sharing class CORE_GEMS2PublicGroupHandler extends CORE_GEMS2UserProvisioningHandler {
    public CORE_GEMS2PublicGroupHandler() {
        if(System.Label.Core_DebugMode == 'TEST')
 { system.debug('In Public Group Handler');}
        stepName = 'CORE_GEMS2PublicGroupHandler';
    }

    public override Result handleRequest() {
        ID userId = null;
        Set < String > newPublicGroupSet = new Set < String > (); // COntains all then new public groups.
        //Map < String, String > mapAccountGSSNwithCountrycode = new Map < String, String > ();
        Map < String, Account > accountMapwithRetailer = New Map < String, Account > ();
        Map < String, Account > mapOfListAccount = new Map < String, Account > ();
        Map < String, Account > mapOfListOldAccount = new Map < String, Account > ();        
        CORE_GEMS2UserProvisioningHandler.Result pgGroup = new CORE_GEMS2UserProvisioningHandler.Result();
        Set < String > accountOrgIdSet = new Set < String > ();
        Account primaryAccount = new Account();
        //Intitialize the gems user payload 
        CORE_GEMS2Payload.GEMS_User userFromGems = payload.userfromGems;
        String userType= userFromGems.usertype;
        //Get market level handler.
        List < Core_Market_Level_Handler__mdt > marketLevelHandlerList = [Select Core_Allowed_Markets__c, DeveloperName from Core_Market_Level_Handler__mdt where
            Core_Component_Type__c = 'Apex Class'
            and Core_Object_Name_Class__c = 'CORE_GEMSUserProvisioningBatch'
            LIMIT 50
        ];
        // this needs to be changed in future.
        Map < string, string > marketLevelCheckPointToAllowedMarketMap = UtilityClass.populateMarketLevelHandlerMap(marketLevelHandlerList);
        //Intialize the UserID from the payload
        String uId = userFromGems.newAttrs.containsKey('uid') ? userFromGems.newAttrs.get('uid')[0] : null;
          
        User usr = null;
        List<User> userList = (List<User>) payload.unitOfWork.getNewListOfRecordsOfType('User');

        if(userList.isEmpty()) {
            Map<Id, SObject> userMap = (Map<Id, SObject>) payload.unitOfWork.getDirtyMapOfRecordsOfType('User');
            if(userMap.isEmpty()) {
                throw new CORE_PreconditionException('CORE_GEMS2PublicGroupHandler handleRequest() userList not set (is empty)');
            } else if(1 < userMap.size()) {
                throw new CORE_PreconditionException('CORE_GEMS2PublicGroupHandler handleRequest() userMap have more than 1 element: ' + userMap);                            
            } else {
                usr = (User)userMap.values()[0];
           }
        } else if(1 < userList.size()) {
            throw new CORE_PreconditionException('CORE_GEMS2PublicGroupHandler handleRequest() userList have more than 1 element: ' + userList);            
        } else {
            usr = userList[0];
        }
        
        String pname = payload.profileName; // This can be added in the Payload as the att
        accountOrgIdSet.addAll(payload.userfromGems.allAccountOIDS); //newattribute account List    
        primaryAccount = userFromGems.Acc;// Primary account which is associated with Contact
        List < Account > accountlist = getAccountsListByGssnOrgId(accountOrgIdSet); //newattribute list of new Account
        
        // Map created of account CORE_GSSN_OrgId__c (D-Outlet.5310001960)field  With Account

        // Not sure why this is needed
        for (Account acc: accountlist) {
            accountMapwithRetailer.put(acc.CORE_GSSN_OrgId__c, acc); // D-Outlet.5310001960=>AccountRecord
        }
        //This map contains all the Retial master data as per the new attr account, Child and Parent of attr Accounts.
        mapOfListAccount = getAccountInformation(accountList, marketLevelCheckPointToAllowedMarketMap);        
        newPublicGroupSet.addall(getRetailBDCPublicGroup(userFromGems.entitlments,mapOfListAccount, 
        pname, Usertype));
        newPublicGroupSet.addall(getMocRelatedNewAttrPublicGroup( userFromGems.entitlments,
             mapOfListAccount,  UserType, accountMapwithRetailer, pname));
        newPublicGroupSet.addall(newEntitlementBasedPublicGroup(userFromGems.entitlments,
             accountMapwithRetailer,UserType, mMOCOwnerToMarketProfile));
        newPublicGroupSet.addall(getCompanyPublicgroup(userFromGems.entitlments, accountMapwithRetailer)) ;

        List<GroupMember> removedGroupMember= reteriveExistingPublicGroupMember(newPublicGroupSet,usr);
        if(removedGroupMember.size()>0){
          	payload.unitOfWork.registerDeleted(removedGroupMember);
        }
        List<GroupMember> newGroupMember= createNewPublicGroupMember(newPublicGroupSet,usr);   
        if(newGroupMember.size()>0){   
            payload.unitOfWork.registerNew(newGroupMember);
        }
        result = new Result('success', stepName);
        return Result;
    }
    /***
     * @description createNewPublicGroupMember Create the group member as per the new group list
     * @param  Usr  current user
     * @return     return lsit of group member list
     */

    private List<groupMember> createNewPublicGroupMember(Set < String > newPublicGroupSet,User usr){

        List<GroupMember> groupMembersList= New List<GroupMember>();
        for(Group gp: [SELECT id,name from group where name in :newPublicGroupSet]){
            GroupMember gm= new GroupMember();
            gm.groupId=gp.id;
            payload.unitOfWork.registerRelationship(gm, GroupMember.UserOrGroupId, usr);
            //GroupMember gm= new GroupMember(UserOrGroupId=UserId, groupid= gp.id);
            groupMembersList.add(gm);
        }
        return groupMembersList;
    }

    /***
     * @description reteriveExistingPublicGroupMember Query existing public gourp and remove the public groups which were part of old Attr
     * @param  Usr Usr User Instance
     * @return return description // This Might not work (Technical issue)
     */ 
    private List<groupMember> reteriveExistingPublicGroupMember(Set < String >  newPublicGroupSet,User usr){

        List<GroupMember> groupMembersList= New List<GroupMember>();
        for(GroupMember gm: [SELECT id,group.name,UserOrGroupId from groupMember 
                    where UserOrGroupId =:usr.id and group.name NOT In: newPublicGroupSet ]){
                        groupMembersList.add(gm);
        }
        return groupMembersList;
    }

    // THis method are defind to set the vairous tupes of Retialer types.

    private static set<string> getRetailerTypes(){
        set < String > setofRetailerType = new set < String > ();
        setofRetailerType.add(System.label.CORE_Org_Level_Location);
        setofRetailerType.add(System.label.CORE_OrganizationLevel_Retailer_Location_Own_Retail);
        setofRetailerType.add(System.label.CORE_OrganizationLevel_Dealer);
        setofRetailerType.add(System.label.CORE_OrganizationLevel_Dealer_Own_Retail);
        return setofRetailerType;
    }
    
    // This method is to assign the User to the Retial BC
    public static set < String > getRetailBDCPublicGroup(List<CORE_GEMS2Payload.Entitlement> entitlments,
                 Map < String, Account > mapOfListAccount, 
                 string profileName, 
                 string userType) {

        set < String > publicGroupSet = new set < String > ();
        set < String > setofRetailerType = new set < String > ();
        set < String > rightstoGive= new Set<String >();
        setofRetailerType.addAll(getRetailerTypes());

        Account acc = new Account();
        for (CORE_GEMS2Payload.Entitlement entitlement: entitlments) {
            if (mapOfListAccount.containsKey(entitlement.oID)) {
                acc = mapOfListAccount.get(entitlement.oID);
            }
            //US13597-If user is from Market DE and Stationary profile , add to DE Non-BDC Retailer Public Group
            //System.Label.Core_Retail_BDC_Profile is not added in the below condition as Retail BDC users are set up for Non DE markets.
            if (profileName == System.Label.CORE_Profile_Community_User_2_0 &&
                acc.core_Market__c == System.Label.CORE_Germany_Country_Code) {
                publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Non_BDC_Retailer_Public_Group__c);
            }
            rightsToGive.add(entitlement.functionalRole);
        }

        if (setofRetailerType.contains(acc.CORE_Outlettype__c) &&
            acc.core_Market__c == System.Label.CORE_Germany_Country_Code && 
            rightsToGive.contains(System.Label.CORE_Retail_Group_Manager)) {
            // Add Retialer Level BDC groupe
            //publicGroupSet.add(System.Label.CORE_DE_BDC_Manager);
            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_BDC_Manager_Public_Group__c);
            
        }
        return publicGroupSet;
    }

    // THis method should be used only to do activity related to Account Role and entitlment value in the newattr.
    public static Set < String > getMocRelatedNewAttrPublicGroup(List<CORE_GEMS2Payload.Entitlement> entitlments,
        Map < String, Account > mapOfListAccount, String userType,
        Map < String, Account > accountMapwithRetailer,
        String pname) {
        Set < String > publicGroupSet = new Set < String > ();
        Account acc = new Account();
        Account primaryAccountForManager = new Account();
        set < String > setofRetailerType = new set < String > ();
        setofRetailerType.addAll(getRetailerTypes());


        for (CORE_GEMS2Payload.Entitlement entitlement: entitlments) {
            if ((!mapOfListAccount.isEmpty()) && mapOfListAccount.containsKey(entitlement.oID)) {

                if (setofRetailerType.contains(acc.CORE_Outlettype__c) &&
                    usertype == 'Retail Group Manager and Retail Group Call Agent') {
                    primaryAccountForManager = accountMapwithRetailer.get(entitlement.oID);
                } else {
                    primaryAccountForManager = mapOfListAccount.get(entitlement.oID);
                }

                acc = mapOfListAccount.get(entitlement.oID);

                if ((!mapOfListAccount.isEmpty()) && mapOfListAccount.containsKey(entitlement.oID)) {
                    if (acc.CORE_Outlettype__c == System.Label.CORE_Role_HQ) {
                        if ((entitlement.functionalRole == System.Label.CORE_Administrator) ||
                            (entitlement.functionalRole == System.Label.CORE_Data_Handler)) {
                            publicGroupSet.add(System.Label.CORE_Data_Handler);
                        }
                    }
                    if (acc.CORE_Outlettype__c == System.Label.OrganizationLevel_MOC ||
                        acc.CORE_Outlettype__c == System.Label.CORE_Org_Level_MOC_OnlineStore) {
                           
                        //CRM-18213 Bindu
                        if ((entitlement.functionalRole == System.Label.Manager) &&
                            (accountMapwithRetailer.get(entitlement.oID).Core_Country__c == acc.Core_Country__c)) {                         
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_MOC_Manager_Public_Group__c);
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Market_Manager_Public_Group__c);
                            
                        }
                        if ((accountMapwithRetailer.get(entitlement.oID).Core_Country__c  == acc.Core_Country__c) &&
                            (entitlement.functionalRole == System.Label.CORE_GateKeeper)) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_MOC_Gatekeeper_Public_Group__c);
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Market_Level_Gatekeeper_Public_Grp__c);
                        }
                        // Sanjay Nandi: SN2021 How to get know if the user is a Campaign Member?

                        if ((accountMapwithRetailer.get(entitlement.oID).Core_Country__c  == acc.Core_Country__c) &&
                            ((entitlement.functionalRole == System.Label.CORE_Campaign_Administrator) ||
                                (entitlement.functionalRole == System.Label.CORE_Campaign_Administrator_PS))) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Campaign_Administrator_Public_Group__c);
                        }
                        // Sanjay Nandi: SN2021 How to get know if the user is a data handler?
                        if ((entitlement.functionalRole == System.Label.CORE_Administrator) || (entitlement.functionalRole == System.Label.CORE_Data_Handler)) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Data_Handler_Public_Group__c);
                        }
                        //Sanjay Nandi  how do we find team lead. and what is TILDA?
                        if (entitlement.functionalRole == System.Label.CORE_Sales_Team_Lead) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_MOC_Sales_Team_Lead_Public_Group__c);
                        }

                    } else if (acc.CORE_Outlettype__c == System.Label.CORE_Role_HQ) {
                        if (entitlement.functionalRole == (System.Label.CORE_Data_Handler)) {
                            publicGroupSet.add(System.Label.CORE_Data_Handler);
                        }
                    } else {

                        if (entitlement.functionalRole == (System.Label.Manager)) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Retailer_Manager_Public_Group__c);
                            //CRM-11496 - Add market specific manager Public Group 
                            publicGroupSet.addall(getManagerPublicGroup(primaryAccountForManager));
                        }

                        if (entitlement.functionalRole == System.Label.CORE_Sales_Team_Lead) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Retailer_Sales_Team_Lead_Public_Grp__c);
                        }
                        //US 13597 - If 'Manager' permission set is assigned , add to the respective Market Level Manager Public Group 
                        if (acc.Core_Country__c != Null && entitlement.functionalRole == System.Label.Manager) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Market_Manager_Public_Group__c);
                        }
                        //US13597-If 'Gatekeeper' permission set is assigned , add to the respective Market Level Gatekeeper Public Group 
                        if (acc.Core_Country__c != Null && entitlement.functionalRole == (System.Label.CORE_GateKeeper)) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Market_Level_Gatekeeper_Public_Grp__c);
                            //CRM 19242 - Add users with GK Stationary to respective Retailer Gatekeeper Public Group
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Retailer_Gatekeeper_Public_Group__c);
                        }
                        //US13597-If user is from Market DE and Stationary profile , add to DE Non-BDC Retailer Public Group
                        //System.Label.Core_Retail_BDC_Profile is not added in the below condition as Retail BDC users are set up for Non DE markets.
                        if (pname != Null && pname == System.Label.CORE_Profile_Community_User_2_0 && acc.Core_Market__c == System.Label.CORE_Germany_Country_Code) {
                            publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Non_BDC_Retailer_Public_Group__c);
                        }
                    }

                }
            }
            if(System.Label.Core_DebugMode == 'TEST')
 { system.debug('Sanjay Public Group:'+publicGroupSet);}
        }
        return publicGroupSet;
    }

// Public group entilement based public group

    public static Set < string > newEntitlementBasedPublicGroup(List<CORE_GEMS2Payload.Entitlement> entitlments,
        Map < String, Account > accountMapwithRetailer,
        String tempUserType,
        Map < String, Market_Profile_Setting__c > mMOCOwnerToMarketProfile) {
        Set < string > publicGroupSet = new Set < String > ();
        if (tempUserType.equalsIgnoreCase(System.Label.CORE_Internal_MOC)) {
            for (CORE_GEMS2Payload.Entitlement entitlement: entitlments) {
                Account acc = new Account();
                acc = accountMapwithRetailer.get(entitlement.oID);
                if (entitlement.functionalRole == System.Label.CORE_Campaign_Administrator) {
                    publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Campaign_Administrator_Public_Group__c);
                }
                if ((entitlement.functionalRole == System.Label.CORE_Administrator ||
                        (entitlement.functionalRole == System.Label.CORE_Data_Handler))) {
                    publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Data_Handler_Public_Group__c);
                }
                if (entitlement.functionalRole == System.Label.CORE_GateKeeper) {
                    publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Market_Level_Gatekeeper_Public_Grp__c);
                }
                if ((entitlement.functionalRole == System.Label.Manager)) {
                    publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Market_Manager_Public_Group__c);
              }
            }

            // add other variants    
        }

        // This is primary related to Retailer.
        if (tempUserType.equalsIgnoreCase(System.Label.CORE_Retailer) ||
            tempUserType == 'Retail Group Manager and Retail Group Call Agent') {
            for (CORE_GEMS2Payload.Entitlement entitlement: entitlments) {
                Account acc = new Account();
                acc = accountMapwithRetailer.get(entitlement.oID);
                if ((entitlement.functionalRole == System.Label.Manager)) {
                    publicGroupSet.add(acc.MOC_Owner__c.substringafter('MOC ') + ' ' + System.Label.CORE_Market_Level_Manager_Public_Group);
                    publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Retailer_Manager_Public_Group__c);
                }
                if (entitlement.functionalRole == System.Label.CORE_GateKeeper) {
                    publicGroupSet.add(acc.MOC_Owner__c.substringafter('MOC ') + ' ' + System.Label.CORE_Market_Level_Gatekeeper);
                    //CRM 19242 - Add users with GK Stationary to respective Retailer Gatekeeper Public Group
                    publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Retailer_Gatekeeper_Public_Group__c);
                }
                if (entitlement.functionalRole == System.Label.CORE_Sales_Team_Lead) {
                    // Missing Code for Market level Team lead.
                    //  publicGroupSet.add(acc.MOC_Owner__c.substringafter('MOC ')+' '+System.Label.);
                    publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Retailer_Sales_Team_Lead_Public_Grp__c);
                }

                // add other variants    
            }
        }

        for (CORE_GEMS2Payload.Entitlement entitlement: entitlments) {
            Account acc = new Account();
            acc = accountMapwithRetailer.get(entitlement.oID);
            if (acc.CORE_Outlettype__c == System.Label.OrganizationLevel_MOC ||
                acc.CORE_Outlettype__c == System.Label.CORE_Org_Level_MOC_OnlineStore
            ) {
                {

                    if (entitlement.functionalRole == System.Label.CORE_GateKeeper) {
                        publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_MOC_Gatekeeper_Public_Group__c);
                    }
                    if ((entitlement.functionalRole == System.Label.Manager)) {
                        publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_MOC_Manager_Public_Group__c);
                    }
                    if (entitlement.functionalRole == System.Label.CORE_Campaign_Administrator) {
                        publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Campaign_Administrator_Public_Group__c);
                    }
                    if ((entitlement.functionalRole == System.Label.CORE_Administrator ||
                            (entitlement.functionalRole == System.Label.CORE_Data_Handler))) {
                        publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_Data_Handler_Public_Group__c);
                    }
                    if (entitlement.functionalRole == System.Label.CORE_Sales_Team_Lead) {
                        publicGroupSet.add(mMOCOwnerToMarketProfile.get(acc.MOC_Owner__c).CORE_MOC_Sales_Team_Lead_Public_Group__c);
                    }
                }
            }

        }
        return publicGroupSet;
    }


    // This is sharing of the public group as per the entitlement Outlet Id 
    public static Set < string > getCompanyPublicgroup(List<CORE_GEMS2Payload.Entitlement> entitlments,
                     Map < String, Account > accountMapwithRetailer) {
        //userFromGems

        Set < string > publicGroupSet = new Set < String > ();
        if (!entitlments.isEmpty() )     {
            for (Account acc: accountMapwithRetailer.values()) {
                publicGroupSet.add(acc.Core_Sharing_Level_ID__c + ' ' + System.Label.CORE_Public_Group);
            }
        }
        return publicGroupSet;
    }

    public static Set < string > formRemovalPublicgroup( Set < string > newPublicGroupSet,
        set<String> oldPublicGroupSet) {
        //Starts here to

        //  Map<string> oldAccSharingCode= New Map<string>();
        Set < string > removedPublicGroupSet = new Set < String > ();
        for (String oldAcc: oldPublicGroupSet) {
            if (!newPublicGroupSet.contains(oldAcc)) {
                removedPublicGroupSet.add(oldAcc);
                // oldAccSharingCode(oldAcc.CORE_GSSN_OrgId__c);
            }
        }
        return removedPublicGroupSet;
    }

    private static user getUser(string uId) {

        user usr = new User();
        usr = NULL;
        for (user u: [select id, Core_Market__c, UserRole.Name, ProfileId, Profile.name from user where FederationIdentifier =: uId limit 1]) {
            usr = u;
        }
        return usr;
    }


    private static Map < String, Account > getAccountInformation(List < Account > accountsList, 
                                Map < string, string > marketLevelCheckPointToAllowedMarketMap) {

        Set < Id > germanyDealerGroupIdSet = new Set < Id > ();
        List < Account > childAccountList = new List < Account > ();
        Map < String, Account > mapOfListAccount = new Map < String, Account > ();
        for (Account acc: accountsList) {

            //IF USER BELONGS TO LOCATION OF VD GROUP(INTERNAL VD USER WITH NO ROLE)/stationary
            if (checkDELocationAndGrandParentDG(acc, marketLevelCheckPointToAllowedMarketMap)) {
                if (acc.Parent.Id != null) {
                    germanyDealerGroupIdSet.add(acc.Parent.Id);
                }
                if (acc.Parent.Parent.Id != null) {
                    germanyDealerGroupIdSet.add(acc.Parent.Parent.Id);
                }
                if (acc.Parent.Parent.Parent.Id != null) {
                    germanyDealerGroupIdSet.add(acc.Parent.Parent.Parent.Id);
                }
                //TO GET ALL CHILD DEALERS OF THIS DEALER GROUP
                germanyDealerGroupIdSet.add(acc.Parent.Parent.Id);
            }
            //IF USER BELONGS TO DEALER OF LEGAL ENTITY(STATIONARY USER)
            if (checkDEDealerAndParentLE(acc, marketLevelCheckPointToAllowedMarketMap)) {
                //TO GET ALL CHILD LOCATIONS
                germanyDealerGroupIdSet.add(acc.Id);
            }
            //IF USER BELONGS TO DEALER OF VD GROUP(INTERNAL VD USER WITH NO ROLE)
            if (checkDEDealerAndParentDealerGroup(acc, marketLevelCheckPointToAllowedMarketMap)) {
                //TO GET ALL CHILD LOCATIONS
                germanyDealerGroupIdSet.add(acc.Parent.Id);
                germanyDealerGroupIdSet.add(acc.Id);
            }

            //IF USER BELONGS TO LEGALENTITY (STATIONARY USER)
            if ((acc.CORE_Outlettype__c == System.Label.CORE_Org_Level_LegalEntity || acc.CORE_Outlettype__c == System.Label.CORE_Org_Level_FSMOC) &&
                acc.CORE_Country__c == System.Label.CORE_Germany_Country_Code) {
                if (acc.ChildAccounts.size() > 0) {
                    for (Account accnt: acc.ChildAccounts) {
                        //TO GET ALL CHILD LOCATIONS OF DEALERS UNDER THAT LEGAL ENTITY
                        germanyDealerGroupIdSet.add(accnt.Id);
                    }
                }
            }

            //IF USER BELONGS TO MOC(INTERNAL USER WITH MOC DE ROLE)
            mapOfListAccount.put(acc.CORE_GSSN_OrgId__c, acc);
        }

        if (!germanyDealerGroupIdSet.isEmpty()) {
            childAccountList = [SELECT Id, Parent.CORE_GSSN_OrgId__c, CORE_GSSN_OrgId__c,
                CORE_Outlettype__c, Parent.Id, Core_Sharing_Level_ID__c,Core_Market__c,
                MOC_Owner__c, CORE_OutletId__c, Core_Country__c,
                (SELECT Id, Parent.CORE_GSSN_OrgId__c, CORE_GSSN_OrgId__c,
                    CORE_Outlettype__c, Parent.Id, Core_Sharing_Level_ID__c,
                    MOC_Owner__c, CORE_OutletId__c,Core_Market__c, Parent.Parent.Id, Core_Country__c FROM ChildAccounts)
                FROM Account WHERE Parent.Id IN: germanyDealerGroupIdSet LIMIT 50000
            ];
        }
        for (Account accObj: childAccountList) {
            mapOfListAccount.put(accObj.CORE_GSSN_OrgId__c, accObj);
        }
        //Sanjay all the above are not required as we will never be able to get an GSSN org Id which is not present 
        //in entitlement so i believe all the above code is unnessary 
        return mapOfListAccount;
    }


    private static Boolean checkDELocationAndGrandParentDG(Account acc, Map < string, string > marketLevelCheckPointToAllowedMarketMap) {
        //CRM-9919 Modified by Ravi
        return ((acc.CORE_Outlettype__c == System.Label.CORE_Org_Level_Location || acc.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Retailer_Location_Own_Retail)
            //   && acc.CORE_Country__c == System.Label.CORE_Germany_Country_Code
            &&
            acc.CORE_Country__c != null &&
            marketLevelCheckPointToAllowedMarketMap.get('Generic_AC_Gen_Check_Point_45').contains(acc.CORE_Country__c) &&
            acc.Parent.Parent.Id != null &&
            (acc.Parent.Parent.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_GROUP || acc.Parent.Parent.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_Group_Own_Retail));
    }
    private static Boolean checkDEDealerAndParentLE(Account acc, Map < string, string > marketLevelCheckPointToAllowedMarketMap) {
        //CRM-9919 Modified by Ravi
        return ((acc.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer || acc.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_Own_Retail)
            //     && acc.CORE_Country__c == System.Label.CORE_Germany_Country_Code
            &&
            acc.CORE_Country__c != null &&
            marketLevelCheckPointToAllowedMarketMap.get('Generic_AC_Gen_Check_Point_55').contains(acc.CORE_Country__c) &&
            acc.Parent.Id != null &&
            acc.Parent.CORE_Outlettype__c == System.Label.CORE_Org_Level_LegalEntity);
    }
    private static Boolean checkDEDealerAndParentDealerGroup(Account acc, Map < string, string > marketLevelCheckPointToAllowedMarketMap) {
        //CRM-9919 Modified by Ravi
        return ((acc.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer || acc.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_Own_Retail) &&
            acc.CORE_Country__c == System.Label.CORE_Germany_Country_Code &&
            acc.Parent.Id != null &&
            (acc.Parent.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_GROUP || acc.Parent.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_Group_Own_Retail));
    }

    private static List < Account > getAccountsListByGssnOrgId(Set < String > accountOrgIdSet) {
        List < Account > accountsList = new List < Account > ();
        accountsList = [SELECT Id, Name, Parent.CORE_GSSN_OrgId__c, CORE_GSSN_OrgId__c,
            CORE_Outlettype__c, Parent.Id, Core_Sharing_Level_ID__c,Core_Market__c,
            MOC_Owner__c, CORE_OutletId__c, CORE_Country__c, Parent.CORE_OutletId__c, Parent.Parent.CORE_OutletId__c,
            Parent.CORE_Outlettype__c, Parent.Parent.CORE_Outlettype__c,
            Parent.Parent.Parent.CORE_Outlettype__c, Parent.Parent.Id, Parent.Parent.Parent.Id,
            (SELECT Id, Name, Parent.CORE_GSSN_OrgId__c, CORE_GSSN_OrgId__c, CORE_Country__c,
                CORE_Outlettype__c, Parent.Id, Core_Sharing_Level_ID__c,
                MOC_Owner__c, CORE_OutletId__c,Core_Market__c FROM ChildAccounts)
            FROM Account WHERE CORE_GSSN_OrgId__c IN: accountOrgIdSet LIMIT 50000
        ];
        return accountsList;
    }

    private static Map < string, Market_Profile_Setting__c > mMOCOwnerToMarketProfile {
        get {
            if (mMOCOwnerToMarketProfile == null) {
                mMOCOwnerToMarketProfile = new Map < string, Market_Profile_Setting__c > ();
                for (Market_Profile_Setting__c market: [Select id,
                                                             name,
                                                             Core_BDC_All_Level_Public_group__c,
                                                             CORE_Market_Manager_Public_Group__c,
                                                             CORE_BDC_Manager_Public_Group__c,
                                                             CORE_Market_Level_Gatekeeper_Public_Grp__c,
                                                             CORE_Dealer_Group_All_Users_Public_Group__c,
                                                             CORE_Public_group_ID_of_MOC__c,
                                                             CORE_Public_Retailer_GroupID__c,
                                                             CORE_Non_BDC_Retailer_Public_Group__c, 
                                                             CORE_MOC_Escalation_Public_Group__c, 
                                                             CORE_MOC_Gatekeeper_Public_Group__c,
                                                             CORE_MOC_All_Users_Public_Group__c, 
                                                             CORE_MOC_Manager_Public_Group__c,
                                                             CORE_Data_Handler_Public_Group__c,
                                                             CORE_Campaign_Administrator_Public_Group__c,
                                                             CORE_Main_Outlet_Manager_Public_Group__c,
                                                             CORE_Sub_Outlet_Manager_Public_Group__c, 
                                                             CORE_MOC_Sales_Team_Lead_Public_Group__c, 
                                                             CORE_Retailer_Gatekeeper_Public_Group__c, 
                                                             CORE_Retailer_Manager_Public_Group__c, 
                                                             CORE_Retailer_Sales_Team_Lead_Public_Grp__c 
                                                             from Market_Profile_Setting__c limit 100]) {
                    mMOCOwnerToMarketProfile.put(market.name, market);
                }
            }
            return mMOCOwnerToMarketProfile;
        }
        set;
    }

    private static set < string > getManagerPublicGroup(Account primaryAccount) {
        Set < String > publicGroupSet = new Set < String > ();
        switch on primaryAccount.Core_Country__c {

            when 'DE' {
                if (primaryAccount.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_Group_Own_Retail || primaryAccount.CORE_Outlettype__c == System.Label.CORE_OrganizationLevel_Dealer_Group) {
                    publicGroupSet.add(System.Label.CORE_DE_BDC_Manager);
                } else if (primaryAccount.CORE_Outlettype__c == System.label.CORE_OrganizationLevel_Dealer || primaryAccount.CORE_Outlettype__c == System.label.CORE_OrganizationLevel_Dealer_Own_Retail) {
                    publicGroupSet.add(System.Label.CORE_DE_Main_Outlet_Manager);
                } else if (primaryAccount.CORE_Outlettype__c == System.label.CORE_Org_Level_Location || primaryAccount.CORE_Outlettype__c == System.label.CORE_OrganizationLevel_Retailer_Location_Own_Retail) {
                    publicGroupSet.add(System.Label.CORE_DE_Sub_Outlet_Manager);
                }

            }
            when 'BE', 'SE','CH' {
                if (primaryAccount.Core_Country__c == 'SE' && (primaryAccount.CORE_Outlettype__c == System.label.CORE_Org_Level_Location || primaryAccount.CORE_Outlettype__c == System.label.CORE_OrganizationLevel_Retailer_Location_Own_Retail)) {
                    publicGroupSet.add(System.Label.CORE_SWE_Sub_Outlet_Manager);
                } else if (primaryAccount.Core_Country__c == 'BE' && (primaryAccount.CORE_Outlettype__c == System.label.CORE_Org_Level_Location || primaryAccount.CORE_Outlettype__c == System.label.CORE_OrganizationLevel_Retailer_Location_Own_Retail)) {
                    publicGroupSet.add(primaryAccount.MOC_Owner__c.substringafter('MOC ') + ' ' + System.Label.CORE_Sub_Outlet_Manager);
                }
                else if (primaryAccount.Core_Country__c == 'CH' && (primaryAccount.CORE_Outlettype__c == System.label.CORE_Org_Level_Location || primaryAccount.CORE_Outlettype__c == System.label.CORE_OrganizationLevel_Retailer_Location_Own_Retail)) {
                    publicGroupSet.add(primaryAccount.MOC_Owner__c.substringafter('MOC ') + ' ' + System.Label.CORE_Sub_Outlet_Manager);
                }

            }
            when 'CZ', 'PL', 'SK', 'HU', 'RO', 'DK', 'NL', 'AT', 'GR', 'PT' {
                if (primaryAccount.CORE_Outlettype__c == System.label.CORE_Org_Level_Location) {
                    publicGroupSet.add(primaryAccount.MOC_Owner__c.substringafter('MOC ') + ' ' + System.Label.CORE_Sub_Outlet_Manager);
                }

            }
        }
        return publicGroupSet;
    }

}
}
